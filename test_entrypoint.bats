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

@test "SSH uses default identity file if IDENTITYFILE is not set" {
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "IdentityFile=/id_rsa" ]]
}
@test "SSH uses specified identity file if IDENTITYFILE is set" {
  export IDENTITYFILE="/foobar"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "IdentityFile=/foobar" ]]
}

@test "SSH properly maps multiple remote ports to local destinations" {
  export REMOTE_FORWARD="127.0.0.1:980 127.0.0.1:9443"
  export LOCAL_DESTINATION="local:80 local:443"
  run ./entrypoint.sh
  echo $output
  [[ $output =~ "-R 127.0.0.1:980:local:80" ]]
  [[ $output =~ "-R 127.0.0.1:9443:local:443" ]]
}
