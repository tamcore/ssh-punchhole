#!/usr/bin/env bats

load test_fake_ssh

setup() {
  export METRICS_DIR="${BATS_TEST_TMPDIR}/metrics"
  export HTTPD=true
  export METRICS_COLLECTION_INTERVAL=0
  export SSH_PORT=22
  start_fake_ssh
  # busybox ps prints the full argv; the PROXY_PROTOCOL remote command contains "grep"
  ps() { echo "PID USER TIME COMMAND"; echo "${FAKE_SSH_PID} root 0:00 ssh -o x haproxy -vv | grep -q prometheus-exporter"; }
  # Output larger than a pipe buffer, so an early-exiting reader causes SIGPIPE
  ss() { awk 'BEGIN { for (i = 1; i <= 20000; i++) print "cubic bytes_sent:" i " bytes_received:" i " retrans:0/" i }'; }
  # Stops the loop after the first iteration; exit 99 means the loop completed
  sleep() { exit 99; }
  export -f ps ss sleep
}

@test "collector survives one loop with many ss lines and ssh argv containing grep" {
  run bash ./metrics-collector.sh
  echo "status=$status $output"
  [ "$status" -eq 99 ]
  grep -q '^ssh_punchhole_up{.*} 1$' "${METRICS_DIR}/ssh_punchhole.prom"
  grep -q '^ssh_punchhole_bytes_sent_total{.*} 1$' "${METRICS_DIR}/ssh_punchhole.prom"
  grep -q '^ssh_punchhole_retransmits_total{.*} 0$' "${METRICS_DIR}/ssh_punchhole.prom"
}

@test "PROXY_PROTOCOL appends haproxy metrics" {
  export PROXY_PROTOCOL=true
  wget() { [[ "$*" == *"http://127.0.0.1:9101/metrics"* ]] && printf 'haproxy_process_nbthread 4\n'; }
  export -f wget
  run bash ./metrics-collector.sh
  [ "$status" -eq 99 ]
  grep -q '^ssh_punchhole_haproxy_metrics_up{.*} 1$' "${METRICS_DIR}/ssh_punchhole.prom"
  grep -q '^haproxy_process_nbthread 4$' "${METRICS_DIR}/ssh_punchhole.prom"
}

@test "PROXY_PROTOCOL reports haproxy metrics down when fetch fails" {
  export PROXY_PROTOCOL=true
  wget() { printf 'partial'; return 1; }
  export -f wget
  run bash ./metrics-collector.sh
  [ "$status" -eq 99 ]
  grep -q '^ssh_punchhole_haproxy_metrics_up{.*} 0$' "${METRICS_DIR}/ssh_punchhole.prom"
  ! grep -q 'partial' "${METRICS_DIR}/ssh_punchhole.prom"
  grep -q '^ssh_punchhole_up{.*} 1$' "${METRICS_DIR}/ssh_punchhole.prom"
}

@test "Plain mode does not fetch haproxy metrics" {
  wget() { echo called > "${BATS_TEST_TMPDIR}/wget_called"; }
  export -f wget
  run bash ./metrics-collector.sh
  [ "$status" -eq 99 ]
  [ ! -e "${BATS_TEST_TMPDIR}/wget_called" ]
  ! grep -q 'haproxy' "${METRICS_DIR}/ssh_punchhole.prom"
}

teardown() {
  stop_fake_ssh
}
