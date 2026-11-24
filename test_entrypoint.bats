#!/usr/bin/env bats

load test_helper

@test "SSH command includes strict host key checking" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "StrictHostKeyChecking=yes" ]]
}

@test "SSH command includes ExitOnForwardFailure=yes by default" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ExitOnForwardFailure=yes" ]]
}

@test "SSH option ExitOnForwardFailure not overwritten, if defined by user" {
  export SSH_OPTS="ExitOnForwardFailure=foobar"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ExitOnForwardFailure=foobar" ]]
}

@test "SSH uses default port if SSH_PORT is not set" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "-p 22" ]]
}

@test "SSH uses specified port if SSH_PORT is set" {
  export SSH_PORT="2222"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "-p 2222" ]]
}

@test "SSH connects to the specified remote host" {
  export REMOTE_HOST="example.com"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "@${REMOTE_HOST}" ]]
}

@test "SSH uses default identity file path in command" {
  # Verify the SSH command includes the IdentityFile option
  run ./entrypoint.sh
  echo $output
  # Should include -o IdentityFile=<path>
  [[ $output =~ "-o IdentityFile=" ]]
}
@test "SSH uses specified identity file if IDENTITYFILE is set" {
  # Create a test file and set IDENTITYFILE to it
  TEST_ID_FILE="${TEST_DIR}/custom_id_rsa"
  touch "$TEST_ID_FILE"
  export IDENTITYFILE="$TEST_ID_FILE"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "IdentityFile=${TEST_ID_FILE}" ]]
}

@test "SSH properly maps multiple remote ports to local destinations" {
  export REMOTE_FORWARD="127.0.0.1:980 127.0.0.1:9443"
  export LOCAL_DESTINATION="local:80 local:443"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "-R 127.0.0.1:980:local:80" ]]
  [[ $output =~ "-R 127.0.0.1:9443:local:443" ]]
}

# Input Validation Tests

@test "Fails when REMOTE_HOST is not set" {
  unset REMOTE_HOST
  run ./entrypoint.sh
  echo $output
  [ "$status" -eq 1 ]
  [[ $output =~ "REMOTE_HOST is required" ]]
}

@test "Fails when REMOTE_FORWARD is not set" {
  unset REMOTE_FORWARD
  run ./entrypoint.sh
  echo $output
  [ "$status" -eq 1 ]
  [[ $output =~ "REMOTE_FORWARD is required" ]]
}

@test "Fails when LOCAL_DESTINATION is not set" {
  unset LOCAL_DESTINATION
  run ./entrypoint.sh
  echo $output
  [ "$status" -eq 1 ]
  [[ $output =~ "LOCAL_DESTINATION is required" ]]
}

@test "Fails when identity file does not exist" {
  export IDENTITYFILE="/nonexistent/id_rsa"
  run ./entrypoint.sh
  echo $output
  [ "$status" -eq 1 ]
  [[ $output =~ "Identity file /nonexistent/id_rsa not found" ]]
}

@test "Fails when known_hosts file does not exist" {
  export KNOWN_HOSTS="/nonexistent/known_hosts"
  run ./entrypoint.sh
  echo $output
  [ "$status" -eq 1 ]
  [[ $output =~ "Known hosts file /nonexistent/known_hosts not found" ]]
}

# Connection Resilience Tests

@test "SSH includes ServerAliveInterval option with default value" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ServerAliveInterval=10" ]]
}

@test "SSH includes ServerAliveInterval option with custom value" {
  export SSH_SERVER_ALIVE_INTERVAL="20"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ServerAliveInterval=20" ]]
}

@test "SSH includes ServerAliveCountMax option with default value" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ServerAliveCountMax=3" ]]
}

@test "SSH includes ServerAliveCountMax option with custom value" {
  export SSH_SERVER_ALIVE_COUNT_MAX="5"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ServerAliveCountMax=5" ]]
}

@test "SSH includes ConnectTimeout option with default value" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ConnectTimeout=30" ]]
}

@test "SSH includes ConnectTimeout option with custom value" {
  export SSH_CONNECT_TIMEOUT="60"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ConnectTimeout=60" ]]
}

@test "SSH includes TCPKeepAlive option" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "TCPKeepAlive=yes" ]]
}

# Control Socket Tests

@test "SSH includes ControlMaster option" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ControlMaster=auto" ]]
}

@test "SSH includes ControlPath option" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ControlPath=/tmp/ssh-punchhole-%r@%h:%p" ]]
}

@test "SSH includes ControlPersist option" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ControlPersist=10m" ]]
}

# Performance Tests

@test "SSH omits Ciphers option by default" {
  run ./entrypoint.sh
  echo $output
  [[ ! $output =~ "Ciphers=" ]]
}

@test "SSH includes Ciphers option with custom value" {
  export SSH_CIPHER="aes128-gcm@openssh.com"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "Ciphers=aes128-gcm@openssh.com" ]]
}

@test "SSH compression disabled by default" {
  run ./entrypoint.sh
  echo $output
  [[ ! $output =~ "Compression=yes" ]]
}

@test "SSH compression enabled when configured" {
  export SSH_COMPRESSION="yes"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "Compression=yes" ]]
}

@test "SSH omits IPQoS option by default" {
  run ./entrypoint.sh
  echo $output
  [[ ! $output =~ "IPQoS=" ]]
}

@test "SSH includes IPQoS option with custom value" {
  export SSH_IPQOS="throughput"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "IPQoS=throughput" ]]
}

@test "SSH disables unnecessary auth methods" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "PasswordAuthentication=no" ]]
  [[ $output =~ "ChallengeResponseAuthentication=no" ]]
}

# Retry Logic Tests

@test "Displays retry attempt information" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "Attempt 1/" ]]
  [[ $output =~ "Connecting to" ]]
}

@test "Uses custom max retries value" {
  export SSH_MAX_RETRIES="5"
  export SSH_INITIAL_BACKOFF="0"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "Attempt 1/5" ]]
}

# Deduplication Tests

@test "SSH_OPTS ServerAliveInterval not overridden by default" {
  export SSH_OPTS="-o ServerAliveInterval=15"
  run ./entrypoint.sh
  echo $output
  # Should only have ServerAliveInterval=15, not both 15 and 10
  [[ $output =~ "ServerAliveInterval=15" ]]
  [[ ! $output =~ "ServerAliveInterval=10" ]]
}

@test "SSH_OPTS custom options respected" {
  export SSH_OPTS="-o ServerAliveInterval=15 -o ServerAliveCountMax=5 -v"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "ServerAliveInterval=15" ]]
  [[ $output =~ "ServerAliveCountMax=5" ]]
  [[ $output =~ " -v " ]]
  # Defaults should not be added
  [[ ! $output =~ "ServerAliveInterval=10" ]]
  [[ ! $output =~ "ServerAliveCountMax=3" ]]
}

# PROXY protocol tests

capture_remote_cmd() {
  ssh() { printf '%s' "${@: -1}" > "${TEST_DIR}/remote_cmd"; echo "ssh $*" > "${TEST_DIR}/ssh_args"; }
  export -f ssh
}

fake_haproxy() {
  mkdir -p "${TEST_DIR}/bin"
  printf '#!/bin/sh\n[ "$1" = -vv ] && { echo "${FAKE_HAPROXY_VV}"; exit 0; }\necho "$@" > "%s/haproxy.args"\ncat > "%s/haproxy.cfg"\ncat "$5" > "%s/metrics.cfg"\n%s\n' "${TEST_DIR}" "${TEST_DIR}" "${TEST_DIR}" "$1" > "${TEST_DIR}/bin/haproxy"
  chmod +x "${TEST_DIR}/bin/haproxy"
}

@test "PROXY_PROTOCOL disabled keeps plain forwards" {
  export REMOTE_FORWARD="0.0.0.0:5013"
  export LOCAL_DESTINATION="gps:5013"
  run ./entrypoint.sh
  [[ $output =~ "-N -n" ]]
  [[ $output =~ "-R 0.0.0.0:5013:gps:5013" ]]
  [[ $output =~ "ControlPersist=10m" ]]
  [[ ! $output =~ "-R 127.0.0.1:" ]]
}

@test "PROXY_PROTOCOL forwards to loopback offset ports" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="0.0.0.0:80 0.0.0.0:443"
  export LOCAL_DESTINATION="gw:80 gw:443"
  run ./entrypoint.sh
  [[ $output =~ "-R 127.0.0.1:10080:gw:80" ]]
  [[ $output =~ "-R 127.0.0.1:10443:gw:443" ]]
  [[ $output =~ "ControlPersist=no" ]]
  [[ ! $output =~ "-N -n" ]]
}

@test "PROXY_PROTOCOL generates haproxy config with send-proxy-v2 by default" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="0.0.0.0:443 10.1.2.3:80"
  export LOCAL_DESTINATION="gw:443 gw:80"
  capture_remote_cmd
  run ./entrypoint.sh
  cmd=$(cat "${TEST_DIR}/remote_cmd")
  [[ $cmd =~ "bind 0.0.0.0:443"$'\n'"  bind :::443 v6only" ]]
  [[ $cmd =~ "server tunnel 127.0.0.1:10443 send-proxy-v2" ]]
  [[ $cmd =~ "bind 10.1.2.3:80" ]]
  [[ $cmd =~ "server tunnel 127.0.0.1:10080 send-proxy-v2" ]]
}

@test "PROXY_PROTOCOL_VERSION=1 uses send-proxy" {
  export PROXY_PROTOCOL="true"
  export PROXY_PROTOCOL_VERSION="1"
  export REMOTE_FORWARD="443"
  capture_remote_cmd
  run ./entrypoint.sh
  cmd=$(cat "${TEST_DIR}/remote_cmd")
  [[ $cmd =~ "bind 0.0.0.0:443"$'\n'"  bind :::443 v6only" ]]
  [[ $cmd =~ "127.0.0.1:10443 send-proxy"$'\n' ]]
}

@test "Fails on invalid PROXY_PROTOCOL value" {
  export PROXY_PROTOCOL="yes"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "PROXY_PROTOCOL must be 'true' or 'false'" ]]
}

@test "Fails on invalid PROXY_PROTOCOL_VERSION value" {
  export PROXY_PROTOCOL="true"
  export PROXY_PROTOCOL_VERSION="3"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "PROXY_PROTOCOL_VERSION must be '1' or '2'" ]]
}

@test "PROXY_PROTOCOL fails when tunnel port exceeds 65535" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="0.0.0.0:55536"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "must be between 1 and 55535" ]]
}

@test "PROXY_PROTOCOL fails on non-numeric port" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="0.0.0.0:https"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "must be between 1 and 55535" ]]
}

@test "PROXY_PROTOCOL fails when tunnel port collides with public port" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="0.0.0.0:80 0.0.0.0:10080"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "tunnel port 10080 collides" ]]
}

@test "Remote command fails clearly when haproxy is missing" {
  export PROXY_PROTOCOL="true"
  capture_remote_cmd
  run ./entrypoint.sh
  run env PATH=/nonexistent /bin/sh "${TEST_DIR}/remote_cmd" < /dev/null
  [ "$status" -eq 127 ]
  [[ $output =~ "haproxy not found on remote host" ]]
}

@test "Remote haproxy is killed when session stdin closes" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="0.0.0.0:443"
  capture_remote_cmd
  run ./entrypoint.sh
  fake_haproxy "exec sleep 30"
  start=$SECONDS
  run sh -c 'sleep 1 | PATH="$1:$PATH" sh "$2"' _ "${TEST_DIR}/bin" "${TEST_DIR}/remote_cmd"
  (( SECONDS - start < 10 ))
  grep -q "bind :::443 v6only" "${TEST_DIR}/haproxy.cfg"
  grep -q "mode tcp" "${TEST_DIR}/haproxy.cfg"
}

@test "Remote command exits with haproxy status while stdin stays open" {
  export PROXY_PROTOCOL="true"
  capture_remote_cmd
  run ./entrypoint.sh
  fake_haproxy "exit 3"
  mkfifo "${TEST_DIR}/stdin"
  exec 4<>"${TEST_DIR}/stdin"
  run env PATH="${TEST_DIR}/bin:${PATH}" sh "${TEST_DIR}/remote_cmd" <&4
  exec 4>&-
  [ "$status" -eq 3 ]
}

@test "PROXY_PROTOCOL fails fast without retry when haproxy is missing" {
  export PROXY_PROTOCOL="true"
  export SSH_MAX_RETRIES="3"
  ssh() { return 127; }
  export -f ssh
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "haproxy not found or not executable on test.example.com" ]]
  [[ ! $output =~ "Attempt 2/" ]]
}

@test "PROXY_PROTOCOL rejects bind address with unsupported characters" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="1.2.3.4:81,0.0.0.0:443"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "invalid bind address" ]]
}

@test "PROXY_PROTOCOL rejects duplicate public port" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="10.0.0.1:443 10.0.0.2:443"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "duplicate public port 443" ]]
}

@test "PROXY_PROTOCOL rejects port that overflows arithmetic" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="0.0.0.0:18446744073709551696"
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "must be between 1 and 55535" ]]
}

@test "PROXY_PROTOCOL does not wait for control socket after ssh exits 0" {
  export PROXY_PROTOCOL="true"
  capture_remote_cmd
  run ./entrypoint.sh
  [[ $(cat "${TEST_DIR}/ssh_args") =~ "-R 127.0.0.1:" ]]
  [[ $output =~ "Max retries (1) reached" ]]
  [[ ! $output =~ "forked to background" ]]
}

@test "PROXY_PROTOCOL accepts bracketed IPv6 bind address" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="[::]:443"
  capture_remote_cmd
  run ./entrypoint.sh
  cmd=$(cat "${TEST_DIR}/remote_cmd")
  [[ $cmd =~ "bind [::]:443"$'\n' ]]
}

@test "PROXY_PROTOCOL accepts leading zeros in port" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD="127.0.0.1:000443"
  run ./entrypoint.sh
  [[ $output =~ "-R 127.0.0.1:10443:" ]]
}

@test "PROXY_PROTOCOL rejects bind address with tab" {
  export PROXY_PROTOCOL="true"
  export REMOTE_FORWARD=$'1.2.3.4\tx:443'
  run ./entrypoint.sh
  [ "$status" -eq 1 ]
  [[ $output =~ "invalid bind address" ]]
}

@test "PROXY_PROTOCOL ControlPersist=no precedes SSH_OPTS so it wins" {
  export PROXY_PROTOCOL="true"
  export SSH_OPTS="-o controlpersist=10m"
  capture_remote_cmd
  run ./entrypoint.sh
  [[ $(cat "${TEST_DIR}/ssh_args") =~ ^"ssh -o StrictHostKeyChecking=yes -o ControlPersist=no -o controlpersist=10m " ]]
}

@test "PROXY_PROTOCOL gives ssh a stdin that stays open" {
  export PROXY_PROTOCOL="true"
  ssh() { [[ -p /dev/stdin ]] && echo "fifo" > "${TEST_DIR}/stdin_type"; }
  export -f ssh
  run ./entrypoint.sh < /dev/null
  [ "$(cat "${TEST_DIR}/stdin_type")" = "fifo" ]
}

@test "PROXY_PROTOCOL forwards haproxy metrics socket to local port" {
  export PROXY_PROTOCOL="true"
  export HOSTNAME="pod-a"
  export REMOTE_FORWARD="0.0.0.0:443"
  capture_remote_cmd
  run ./entrypoint.sh
  grep -q -- "-L 127.0.0.1:9101:/tmp/ssh-punchhole-metrics-pod-a.sock " "${TEST_DIR}/ssh_args"
}

@test "PROXY_PROTOCOL metrics socket name only uses safe characters" {
  export PROXY_PROTOCOL="true"
  export HOSTNAME='pod/a b;$x'
  capture_remote_cmd
  run ./entrypoint.sh
  grep -q -- "-L 127.0.0.1:9101:/tmp/ssh-punchhole-metrics-pod_a_b__x.sock " "${TEST_DIR}/ssh_args"
}

@test "PROXY_PROTOCOL disabled has no metrics forward" {
  capture_remote_cmd
  run ./entrypoint.sh
  [ "$(grep -c -- "-L " "${TEST_DIR}/ssh_args")" -eq 0 ]
}

@test "Remote command removes metrics socket after haproxy exits" {
  export PROXY_PROTOCOL="true"
  export HOSTNAME="bats-$$-${RANDOM}"
  sock="/tmp/ssh-punchhole-metrics-${HOSTNAME}.sock"
  capture_remote_cmd
  run ./entrypoint.sh
  fake_haproxy "exit 3"
  touch "$sock"
  mkfifo "${TEST_DIR}/stdin"
  exec 4<>"${TEST_DIR}/stdin"
  run env PATH="${TEST_DIR}/bin:${PATH}" sh "${TEST_DIR}/remote_cmd" <&4
  exec 4>&-
  [ "$status" -eq 3 ]
  [ ! -e "$sock" ]
}

run_remote_cmd_with_open_stdin() {
  mkfifo "${TEST_DIR}/stdin"
  exec 4<>"${TEST_DIR}/stdin"
  run env PATH="${TEST_DIR}/bin:${PATH}" sh "${TEST_DIR}/remote_cmd" <&4
  exec 4>&-
}

@test "Remote haproxy loads metrics frontend when it has the Prometheus exporter" {
  export PROXY_PROTOCOL="true"
  export HOSTNAME="pod-a"
  export REMOTE_FORWARD="0.0.0.0:443"
  capture_remote_cmd
  run ./entrypoint.sh
  fake_haproxy "exit 0"
  export FAKE_HAPROXY_VV="Available services : prometheus-exporter"
  run_remote_cmd_with_open_stdin
  grep -q -- "-f /dev/stdin -f /dev/fd/4" "${TEST_DIR}/haproxy.args"
  grep -q "bind :::443 v6only" "${TEST_DIR}/haproxy.cfg"
  [ "$(grep -c "fe_metrics" "${TEST_DIR}/haproxy.cfg")" -eq 0 ]
  grep -q "frontend fe_metrics" "${TEST_DIR}/metrics.cfg"
  grep -q "  mode http" "${TEST_DIR}/metrics.cfg"
  grep -q "bind unix@/tmp/ssh-punchhole-metrics-pod-a.sock mode 600" "${TEST_DIR}/metrics.cfg"
  grep -q "http-request use-service prometheus-exporter" "${TEST_DIR}/metrics.cfg"
}

@test "Remote haproxy skips metrics frontend without the Prometheus exporter" {
  export PROXY_PROTOCOL="true"
  capture_remote_cmd
  run ./entrypoint.sh
  fake_haproxy "exit 0"
  export FAKE_HAPROXY_VV="Available services : none"
  run_remote_cmd_with_open_stdin
  [ "$status" -eq 0 ]
  grep -q -- "-f /dev/stdin -f /dev/null" "${TEST_DIR}/haproxy.args"
  [ ! -s "${TEST_DIR}/metrics.cfg" ]
}
