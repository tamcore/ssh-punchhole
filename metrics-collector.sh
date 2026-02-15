#!/bin/bash
set -euo pipefail

METRICS_DIR="${METRICS_DIR:-/metrics}"
METRICS_FILE="${METRICS_DIR}/ssh_punchhole.prom"
COLLECTION_INTERVAL="${METRICS_COLLECTION_INTERVAL:-30}"
REMOTE_HOST="${REMOTE_HOST:-unknown}"
SSH_PORT="${SSH_PORT:-22}"
HTTP_PORT="${HTTP_PORT:-9090}"

mkdir -p "$METRICS_DIR"
container_start_time=$(date +%s)

# Start httpd in background to expose metrics
# -f: foreground (we'll background it ourselves)
# -p: port
# -h: home directory to serve
cd "$METRICS_DIR"
/usr/sbin/httpd -f -p "$HTTP_PORT" -h "$METRICS_DIR" &
http_server_pid=$!

# Cleanup on exit
trap "kill $http_server_pid 2>/dev/null || true" EXIT

while true; do
  temp_file="${METRICS_FILE}.$$"
  current_time=$(date +%s)

  # Check if SSH process is running
  if ps | grep -v grep | grep -w ssh > /dev/null 2>&1; then
    tunnel_up=1
    ssh_pid=$(ps | grep -v grep | grep -w ssh | awk '{print $1}' | head -1)
    ssh_start_time=$(stat -c %Y /proc/$ssh_pid 2>/dev/null || echo $current_time)
    connection_duration=$((current_time - ssh_start_time))

    # Get network statistics
    bytes_sent=0
    bytes_recv=0
    retrans=0

    if command -v ss >/dev/null 2>&1; then
      ss_output=$(ss -tin "( dport = :${SSH_PORT} or sport = :${SSH_PORT} )" 2>/dev/null || echo "")
      if echo "$ss_output" | grep -q "bytes_sent:"; then
        bytes_sent=$(echo "$ss_output" | sed -n 's/.*bytes_sent:\([0-9]*\).*/\1/p' | head -1)
        bytes_sent=${bytes_sent:-0}
        bytes_recv=$(echo "$ss_output" | sed -n 's/.*bytes_received:\([0-9]*\).*/\1/p' | head -1)
        bytes_recv=${bytes_recv:-0}
      fi
      if echo "$ss_output" | grep -q "retrans:"; then
        retrans=$(echo "$ss_output" | sed -n 's/.*retrans:\([0-9]*\)\/.*/\1/p' | head -1)
        retrans=${retrans:-0}
      fi
    fi
  else
    tunnel_up=0
    connection_duration=0
    bytes_sent=0
    bytes_recv=0
    retrans=0
  fi

  container_uptime=$((current_time - container_start_time))

  # Write metrics in Prometheus format
  cat > "$temp_file" <<EOF
# HELP ssh_punchhole_up Whether the SSH punchhole tunnel is up (1) or down (0)
# TYPE ssh_punchhole_up gauge
ssh_punchhole_up{remote_host="${REMOTE_HOST}",remote_port="${SSH_PORT}"} ${tunnel_up}

# HELP ssh_punchhole_connection_duration_seconds Time since current SSH connection established
# TYPE ssh_punchhole_connection_duration_seconds gauge
ssh_punchhole_connection_duration_seconds{remote_host="${REMOTE_HOST}"} ${connection_duration}

# HELP ssh_punchhole_bytes_sent_total Total bytes sent through SSH connection
# TYPE ssh_punchhole_bytes_sent_total counter
ssh_punchhole_bytes_sent_total{remote_host="${REMOTE_HOST}"} ${bytes_sent}

# HELP ssh_punchhole_bytes_received_total Total bytes received through SSH connection
# TYPE ssh_punchhole_bytes_received_total counter
ssh_punchhole_bytes_received_total{remote_host="${REMOTE_HOST}"} ${bytes_recv}

# HELP ssh_punchhole_retransmits_total TCP retransmissions on SSH connection
# TYPE ssh_punchhole_retransmits_total counter
ssh_punchhole_retransmits_total{remote_host="${REMOTE_HOST}"} ${retrans}

# HELP ssh_punchhole_container_uptime_seconds Time since container started
# TYPE ssh_punchhole_container_uptime_seconds gauge
ssh_punchhole_container_uptime_seconds{remote_host="${REMOTE_HOST}"} ${container_uptime}
EOF

  mv "$temp_file" "$METRICS_FILE"
  sleep "$COLLECTION_INTERVAL"
done
