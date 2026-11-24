#!/usr/bin/env bats

setup() {
  export METRICS_DIR="${BATS_TEST_TMPDIR}/metrics"
  export HTTPD=true
  export METRICS_COLLECTION_INTERVAL=0
  export SSH_PORT=22
  # Output larger than a pipe buffer, so an early-exiting reader causes SIGPIPE
  ps() { awk 'BEGIN { print "PID USER TIME COMMAND"; for (i = 1; i <= 20000; i++) print i " nobody 0:00 ssh -o x" }'; }
  ss() { awk 'BEGIN { for (i = 1; i <= 20000; i++) print "cubic bytes_sent:" i " bytes_received:" i " retrans:0/" i }'; }
  # Stops the loop after the first iteration; exit 99 means the loop completed
  sleep() { exit 99; }
  export -f ps ss sleep
}

@test "collector survives one loop with many ssh processes and ss lines" {
  run bash ./metrics-collector.sh
  echo "status=$status $output"
  [ "$status" -eq 99 ]
  grep -q '^ssh_punchhole_up{.*} 1$' "${METRICS_DIR}/ssh_punchhole.prom"
  grep -q '^ssh_punchhole_bytes_sent_total{.*} 1$' "${METRICS_DIR}/ssh_punchhole.prom"
  grep -q '^ssh_punchhole_retransmits_total{.*} 0$' "${METRICS_DIR}/ssh_punchhole.prom"
}
