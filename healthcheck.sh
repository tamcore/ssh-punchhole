#!/bin/bash
set -e

# Check SSH process running
if ! ps | grep -v grep | grep -w ssh > /dev/null; then
  echo "FAIL: SSH process not running" >&2
  exit 1
fi

# Check SSH control socket exists
CONTROL_PATH="/tmp/ssh-punchhole-${SSH_USER:-root}@${REMOTE_HOST}:${SSH_PORT:-22}"
if [[ ! -S "${CONTROL_PATH}" ]]; then
  echo "FAIL: SSH control socket not found at ${CONTROL_PATH}" >&2
  exit 1
fi

# Check connection is responsive
if ! timeout 5 ssh -o ControlPath="${CONTROL_PATH}" -O check "${SSH_USER:-root}@${REMOTE_HOST}" 2>/dev/null; then
  echo "FAIL: SSH connection not responsive" >&2
  exit 1
fi

echo "OK: Tunnel healthy"
exit 0
