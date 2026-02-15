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

@test "SSH includes Ciphers option with default value" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "Ciphers=chacha20-poly1305@openssh.com" ]]
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

@test "SSH includes IPQoS option with default value" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "IPQoS=lowdelay" ]]
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
