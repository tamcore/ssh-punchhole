#!/bin/bash
set -euo pipefail

METRICS_DIR="${METRICS_DIR:-/metrics}"
METRICS_FILE="${METRICS_DIR}/ssh_punchhole.prom"
COLLECTION_INTERVAL="${METRICS_COLLECTION_INTERVAL:-30}"
REMOTE_HOST="${REMOTE_HOST:-unknown}"
SSH_PORT="${SSH_PORT:-22}"
HTTP_PORT="${HTTP_PORT:-9090}"
HTTPD="${HTTPD:-/usr/sbin/httpd}"
PROXY_PROTOCOL="${PROXY_PROTOCOL:-false}"
HAPROXY_METRICS_URL="http://127.0.0.1:${HAPROXY_METRICS_PORT:-9101}/metrics"
HAPROXY_FETCH_TIMEOUT=5

mkdir -p "$METRICS_DIR"
container_start_time=$(date +%s)

# Start httpd in background to expose metrics
# -f: foreground (we'll background it ourselves)
# -p: port
# -h: home directory to serve
cd "$METRICS_DIR"
"${HTTPD}" -f -p "$HTTP_PORT" -h "$METRICS_DIR" &
http_server_pid=$!

# Cleanup on exit
trap "kill $http_server_pid 2>/dev/null || true" EXIT

while true; do
  temp_file="${METRICS_FILE}.$$"
  current_time=$(date +%s)

  # Check if SSH process is running
  # By name: the PROXY_PROTOCOL remote command in the ssh argv contains "grep"
  if ssh_pid=$(pgrep -o -x ssh); then
    tunnel_up=1
    ssh_start_time=$(stat -c %Y /proc/$ssh_pid 2>/dev/null || echo $current_time)
    connection_duration=$((current_time - ssh_start_time))

    # Get network statistics
    bytes_sent=0
    bytes_recv=0
    retrans=0

    if command -v ss >/dev/null 2>&1; then
      ss_output=$(ss -tin "( dport = :${SSH_PORT} or sport = :${SSH_PORT} )" 2>/dev/null || echo "")
      if [[ $ss_output == *bytes_sent:* ]]; then
        bytes_sent=$(echo "$ss_output" | sed -n 's/.*bytes_sent:\([0-9]*\).*/\1/p' | sed -n 1p)
        bytes_sent=${bytes_sent:-0}
        bytes_recv=$(echo "$ss_output" | sed -n 's/.*bytes_received:\([0-9]*\).*/\1/p' | sed -n 1p)
        bytes_recv=${bytes_recv:-0}
      fi
      if [[ $ss_output == *retrans:* ]]; then
        retrans=$(echo "$ss_output" | sed -n 's/.*retrans:\([0-9]*\)\/.*/\1/p' | sed -n 1p)
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

  if [[ "${PROXY_PROTOCOL}" == "true" ]]; then
    haproxy_file="${temp_file}.haproxy"
    haproxy_up=0
    wget -q -Y off -T "${HAPROXY_FETCH_TIMEOUT}" -O - "${HAPROXY_METRICS_URL}" > "${haproxy_file}" 2>/dev/null && haproxy_up=1
    cat >> "$temp_file" <<EOF

# HELP ssh_punchhole_haproxy_metrics_up Whether the remote haproxy metrics were fetched (1) or not (0)
# TYPE ssh_punchhole_haproxy_metrics_up gauge
ssh_punchhole_haproxy_metrics_up{remote_host="${REMOTE_HOST}"} ${haproxy_up}
EOF
    (( haproxy_up )) && cat "${haproxy_file}" >> "$temp_file"
    rm -f "${haproxy_file}"
  fi

  mv "$temp_file" "$METRICS_FILE"
  sleep "$COLLECTION_INTERVAL"
done
