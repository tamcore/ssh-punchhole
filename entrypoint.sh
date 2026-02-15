#!/bin/bash

set -e  # Exit on error
set -x

# Validate required environment variables
: "${REMOTE_HOST:?ERROR: REMOTE_HOST is required}"
: "${REMOTE_FORWARD:?ERROR: REMOTE_FORWARD is required}"
: "${LOCAL_DESTINATION:?ERROR: LOCAL_DESTINATION is required}"

# Validate files exist
IDENTITYFILE_PATH="${IDENTITYFILE-/id_rsa}"
KNOWN_HOSTS_PATH="${KNOWN_HOSTS-/known_hosts}"

if [[ ! -f "${IDENTITYFILE_PATH}" ]]; then
  echo "ERROR: Identity file ${IDENTITYFILE_PATH} not found" >&2
  exit 1
fi

if [[ ! -f "${KNOWN_HOSTS_PATH}" ]]; then
  echo "ERROR: Known hosts file ${KNOWN_HOSTS_PATH} not found" >&2
  exit 1
fi

# -N Do not execute a remote command.
# -n Redirects stdin from /dev/null
_ssh="ssh -o StrictHostKeyChecking=yes  -N -n ${SSH_OPTS} "

# ExitOnForwardFailure prevents SSH from getting stuck in case of a "Warning: remote port forwarding failed for listen port"
[[ "${SSH_OPTS}" != *ExitOnForwardFailure* ]] && _ssh+="-o ExitOnForwardFailure=yes "

# Connection resilience options
[[ "${SSH_OPTS}" != *ServerAliveInterval* ]] && _ssh+="-o ServerAliveInterval=${SSH_SERVER_ALIVE_INTERVAL-10} "
[[ "${SSH_OPTS}" != *ServerAliveCountMax* ]] && _ssh+="-o ServerAliveCountMax=${SSH_SERVER_ALIVE_COUNT_MAX-3} "
[[ "${SSH_OPTS}" != *ConnectTimeout* ]] && _ssh+="-o ConnectTimeout=${SSH_CONNECT_TIMEOUT-30} "
[[ "${SSH_OPTS}" != *TCPKeepAlive* ]] && _ssh+="-o TCPKeepAlive=yes "

# Control socket for health checks
[[ "${SSH_OPTS}" != *ControlMaster* ]] && _ssh+="-o ControlMaster=auto "
[[ "${SSH_OPTS}" != *ControlPath* ]] && _ssh+="-o ControlPath=/tmp/ssh-punchhole-%r@%h:%p "
[[ "${SSH_OPTS}" != *ControlPersist* ]] && _ssh+="-o ControlPersist=10m "

# Performance options (only if explicitly set, not by default)
if [[ "${SSH_OPTS}" != *Ciphers* ]] && [[ -n "${SSH_CIPHER}" ]]; then
  _ssh+="-o Ciphers=${SSH_CIPHER} "
fi

if [[ "${SSH_OPTS}" != *Compression* ]] && [[ "${SSH_COMPRESSION}" == "yes" ]]; then
  _ssh+="-o Compression=yes "
fi

if [[ "${SSH_OPTS}" != *IPQoS* ]] && [[ -n "${SSH_IPQOS}" ]]; then
  _ssh+="-o IPQoS=${SSH_IPQOS} "
fi

# Disable unnecessary auth methods for faster connection
[[ "${SSH_OPTS}" != *PasswordAuthentication* ]] && _ssh+="-o PasswordAuthentication=no "
[[ "${SSH_OPTS}" != *ChallengeResponseAuthentication* ]] && _ssh+="-o ChallengeResponseAuthentication=no "

_ssh+="-p ${SSH_PORT-22} -o IdentityFile=${IDENTITYFILE-/id_rsa} -o UserKnownHostsFile=${KNOWN_HOSTS-/known_hosts} "

IFS=' ' read -r -a REMOTE_FORWARD <<< "${REMOTE_FORWARD}"
IFS=' ' read -r -a LOCAL_DESTINATION <<< "${LOCAL_DESTINATION}"

len=${#REMOTE_FORWARD[@]}

for (( i=0; i<$len; i++ ))
do
  remote=${REMOTE_FORWARD[$i]}
  local=${LOCAL_DESTINATION[$i]-${LOCAL_DESTINATION[0]}}

  echo "$remote -> $local"

  _ssh+="-R ${remote}:${local} "
done

_ssh+="${SSH_USER-root}@${REMOTE_HOST}"

# Graceful shutdown handling
shutdown_requested=false
ssh_pid=""

handle_shutdown() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Shutdown signal received"
  shutdown_requested=true

  CONTROL_PATH="/tmp/ssh-punchhole-${SSH_USER-root}@${REMOTE_HOST}:${SSH_PORT-22}"
  if [[ -S "${CONTROL_PATH}" ]]; then
    ssh -o ControlPath="${CONTROL_PATH}" -O exit "${SSH_USER-root}@${REMOTE_HOST}" 2>/dev/null || true
  fi

  if [[ -n "$ssh_pid" ]] && kill -0 "$ssh_pid" 2>/dev/null; then
    kill -TERM "$ssh_pid" 2>/dev/null || true
    for i in {1..10}; do
      if ! kill -0 "$ssh_pid" 2>/dev/null; then
        echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] SSH exited cleanly"
        exit 0
      fi
      sleep 1
    done
    kill -KILL "$ssh_pid" 2>/dev/null || true
  fi
  exit 0
}

trap handle_shutdown SIGTERM SIGINT

# Retry configuration
MAX_RETRIES="${SSH_MAX_RETRIES:-10}"
INITIAL_BACKOFF="${SSH_INITIAL_BACKOFF:-5}"
MAX_BACKOFF="${SSH_MAX_BACKOFF:-300}"
BACKOFF_MULTIPLIER="2"

retry_count=0
backoff=$INITIAL_BACKOFF

while true; do
  if [[ "$shutdown_requested" == "true" ]]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Shutdown requested, exiting retry loop"
    exit 0
  fi

  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Attempt $((retry_count + 1))/$MAX_RETRIES: Connecting to ${SSH_USER-root}@${REMOTE_HOST}:${SSH_PORT-22}"

  set +e
  ${_ssh} &
  ssh_pid=$!
  wait $ssh_pid
  exit_code=$?
  set -e

  if [[ $exit_code -eq 0 ]]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] SSH forked to background successfully"
    # SSH with ControlMaster forks to background on successful connection
    # Wait for control socket to disappear (indicates tunnel died)
    CONTROL_PATH="/tmp/ssh-punchhole-${SSH_USER-root}@${REMOTE_HOST}:${SSH_PORT-22}"
    while [[ -S "${CONTROL_PATH}" ]]; do
      sleep 10
    done
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Control socket disappeared, tunnel died"
    # Continue retry loop
  fi

  retry_count=$((retry_count + 1))

  if [[ $retry_count -ge $MAX_RETRIES ]]; then
    echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] ERROR: Max retries ($MAX_RETRIES) reached. Exiting." >&2
    exit 1
  fi

  echo "[$(date -u +"%Y-%m-%dT%H:%M:%SZ")] Connection failed (exit code $exit_code). Retrying in ${backoff}s..."
  sleep $backoff

  backoff=$((backoff * BACKOFF_MULTIPLIER))
  if [[ $backoff -gt $MAX_BACKOFF ]]; then
    backoff=$MAX_BACKOFF
  fi
done
