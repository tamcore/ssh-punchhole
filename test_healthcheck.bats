#!/usr/bin/env bats

load test_fake_ssh

setup() {
  export REMOTE_HOST="hc-test-${RANDOM}.invalid"
  start_fake_ssh
  ps() { echo "PID USER TIME COMMAND"; echo "${FAKE_SSH_PID} root 0:00 ssh -o x haproxy -vv | grep -q prometheus-exporter"; }
  export -f ps
}

teardown() {
  stop_fake_ssh
}

@test "healthcheck finds ssh whose argv contains grep" {
  run bash ./healthcheck.sh
  echo "$output"
  [[ ! $output =~ "SSH process not running" ]]
  [[ $output =~ "SSH control socket not found" ]]
}

@test "healthcheck fails when no ssh process runs" {
  stop_fake_ssh
  command sleep 0.2
  pgrep -x ssh && skip "a real ssh process runs on this host"
  run bash ./healthcheck.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "SSH process not running" ]]
}
