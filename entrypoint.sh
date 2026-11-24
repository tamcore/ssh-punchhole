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

PROXY_PROTOCOL="${PROXY_PROTOCOL:-false}"
PROXY_PROTOCOL_VERSION="${PROXY_PROTOCOL_VERSION:-2}"
PROXY_PROTOCOL_PORT_OFFSET=10000
MAX_PORT=65535
STDIN_FIFO="/tmp/ssh-punchhole-stdin"
HAPROXY_MISSING_EXIT_CODE=127

die() {
  echo "ERROR: $*" >&2
  exit 1
}

case "${PROXY_PROTOCOL}" in
  true|false) ;;
  *) die "PROXY_PROTOCOL must be 'true' or 'false', got '${PROXY_PROTOCOL}'" ;;
esac

if [[ "${PROXY_PROTOCOL}" == "true" && "${SSH_OPTS}" == *ControlPersist* && "${SSH_OPTS}" != *ControlPersist=no* ]]; then
  die "PROXY_PROTOCOL requires ControlPersist=no; remove ControlPersist from SSH_OPTS"
fi

case "${PROXY_PROTOCOL_VERSION}" in
  1) SEND_PROXY="send-proxy" ;;
  2) SEND_PROXY="send-proxy-v2" ;;
  *) die "PROXY_PROTOCOL_VERSION must be '1' or '2', got '${PROXY_PROTOCOL_VERSION}'" ;;
esac

# Separate v4/v6 binds: a v4v6 socket reports IPv4 clients as ::ffff:a.b.c.d in the PROXY header
haproxy_bind() {
  case "$1" in
    ""|"*"|0.0.0.0) printf '  bind 0.0.0.0:%s\n  bind :::%s v6only\n' "$2" "$2" ;;
    *) printf '  bind %s:%s\n' "$1" "$2" ;;
  esac
}

haproxy_frontend() {
  local bind_addr=$1 port=$2 tunnel_port=$3
  cat <<EOF

frontend fe_${port}
$(haproxy_bind "${bind_addr}" "${port}")
  default_backend be_${port}

backend be_${port}
  server tunnel 127.0.0.1:${tunnel_port} ${SEND_PROXY}
EOF
}

# haproxy runs as the remote command; it is killed when the session's stdin hits EOF (connection gone).
haproxy_remote_cmd() {
  cat <<EOF
command -v haproxy >/dev/null 2>&1 || { echo "ERROR: haproxy not found on remote host" >&2; exit ${HAPROXY_MISSING_EXIT_CODE}; }
exec 3<&0
haproxy -db -f /dev/stdin <<'HAPROXY_CFG' &
defaults
  mode tcp
  timeout connect 5s
  timeout client 1h
  timeout server 1h
$1
HAPROXY_CFG
pid=\$!
(cat >/dev/null; kill \$pid 2>/dev/null) <&3 >/dev/null 2>&1 &
wait \$pid
EOF
}

if [[ "${PROXY_PROTOCOL}" == "true" ]]; then
  _ssh="ssh -o StrictHostKeyChecking=yes ${SSH_OPTS} "
else
  # -N Do not execute a remote command.
  # -n Redirects stdin from /dev/null
  _ssh="ssh -o StrictHostKeyChecking=yes  -N -n ${SSH_OPTS} "
fi

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
# PROXY_PROTOCOL: the master must exit with the haproxy session, so its forwards are released
if [[ "${SSH_OPTS}" != *ControlPersist* ]]; then
  [[ "${PROXY_PROTOCOL}" == "true" ]] && _ssh+="-o ControlPersist=no " || _ssh+="-o ControlPersist=10m "
fi

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
haproxy_cfg=""
public_ports=" "
tunnel_ports=""

for (( i=0; i<$len; i++ ))
do
  remote=${REMOTE_FORWARD[$i]}
  local=${LOCAL_DESTINATION[$i]-${LOCAL_DESTINATION[0]}}

  if [[ "${PROXY_PROTOCOL}" != "true" ]]; then
    echo "$remote -> $local"
    _ssh+="-R ${remote}:${local} "
    continue
  fi

  port=${remote##*:}
  bind_addr=""
  [[ "$remote" == *:* ]] && bind_addr=${remote%:*}
  max_public_port=$((MAX_PORT - PROXY_PROTOCOL_PORT_OFFSET))
  if ! [[ "$port" =~ ^0*[0-9]{1,5}$ ]] || (( 10#$port < 1 || 10#$port > max_public_port )); then
    die "PROXY_PROTOCOL: port '${port}' in '${remote}' must be between 1 and ${max_public_port}"
  fi
  [[ "$bind_addr" =~ ^[][0-9A-Za-z.:*_-]*$ ]] || die "PROXY_PROTOCOL: invalid bind address '${bind_addr}' in '${remote}'"
  port=$((10#$port))
  [[ "${public_ports}" == *" ${port} "* ]] && die "PROXY_PROTOCOL: duplicate public port ${port} in REMOTE_FORWARD"
  tunnel_port=$((port + PROXY_PROTOCOL_PORT_OFFSET))

  echo "$remote -> haproxy (${SEND_PROXY}) -> 127.0.0.1:${tunnel_port} -> $local"
  _ssh+="-R 127.0.0.1:${tunnel_port}:${local} "
  haproxy_cfg+=$(haproxy_frontend "${bind_addr}" "${port}" "${tunnel_port}")$'\n'
  public_ports+="${port} "
  tunnel_ports+="${tunnel_port} "
done

for tunnel_port in ${tunnel_ports}; do
  [[ "${public_ports}" == *" ${tunnel_port} "* ]] && die "PROXY_PROTOCOL: tunnel port ${tunnel_port} collides with a public port in REMOTE_FORWARD"
done

_ssh+="${SSH_USER-root}@${REMOTE_HOST}"

remote_cmd=""
if [[ "${PROXY_PROTOCOL}" == "true" ]]; then
  remote_cmd=$(haproxy_remote_cmd "${haproxy_cfg}")
  # Read-write open keeps the FIFO from ever delivering EOF, so the remote stdin stays open while ssh lives
  [[ -p "${STDIN_FIFO}" ]] || mkfifo "${STDIN_FIFO}"
  exec 3<>"${STDIN_FIFO}"
fi

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
  if [[ -n "${remote_cmd}" ]]; then
    ${_ssh} "${remote_cmd}" <&3 &
  else
    ${_ssh} &
  fi
  ssh_pid=$!
  wait $ssh_pid
  exit_code=$?
  set -e

  if [[ -n "${remote_cmd}" ]] && [[ $exit_code -eq ${HAPROXY_MISSING_EXIT_CODE} ]]; then
    die "haproxy not found or not executable on ${REMOTE_HOST}. Install it there (do not enable the system service)."
  fi

  # PROXY_PROTOCOL runs ssh in the foreground with ControlPersist=no, so its exit already means the tunnel ended
  if [[ $exit_code -eq 0 ]] && [[ -z "${remote_cmd}" ]]; then
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
