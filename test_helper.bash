# Setup test environment
setup() {
  # Set required environment variables if not set
  export REMOTE_HOST="${REMOTE_HOST:-test.example.com}"
  export REMOTE_FORWARD="${REMOTE_FORWARD:-127.0.0.1:8080}"
  export LOCAL_DESTINATION="${LOCAL_DESTINATION:-nginx:80}"

  # Create temporary files for SSH keys
  export TEST_DIR="${BATS_TMPDIR}/ssh-punchhole-test"
  mkdir -p "$TEST_DIR"

  # Only set IDENTITYFILE and KNOWN_HOSTS if not already set by the test
  # This allows tests to override the defaults
  if [[ -z "${IDENTITYFILE_OVERRIDE}" ]]; then
    export IDENTITYFILE="${IDENTITYFILE:-${TEST_DIR}/id_rsa}"
  fi
  if [[ -z "${KNOWN_HOSTS_OVERRIDE}" ]]; then
    export KNOWN_HOSTS="${KNOWN_HOSTS:-${TEST_DIR}/known_hosts}"
  fi

  # Create mock SSH key files
  touch "${IDENTITYFILE}"
  touch "${KNOWN_HOSTS}"

  # Also create default paths for tests that unset IDENTITYFILE
  mkdir -p /tmp/ssh-test-defaults
  touch /tmp/ssh-test-defaults/id_rsa
  touch /tmp/ssh-test-defaults/known_hosts

  # Set max retries to 1 for faster test execution
  export SSH_MAX_RETRIES="${SSH_MAX_RETRIES:-1}"
}

# Cleanup test environment
teardown() {
  rm -rf "$TEST_DIR"
}

# Mock SSH command for local testing (bypasses an actual SSH call)
# Exit with 0 to simulate successful connection
ssh() {
  echo "ssh $*"
  return 0
}
export -f ssh

# Mock ps for health check tests
# Output format: PID USER TIME COMMAND
ps() {
  echo "  PID USER     TIME  COMMAND"
  echo " $$ nobody   0:00 ssh -o ..."
  return 0
}
export -f ps

# Mock date for consistent timestamps
date() {
  if [[ "$1" == "-u" ]] && [[ "$2" == "+%Y-%m-%dT%H:%M:%SZ" ]]; then
    echo "2024-01-01T00:00:00Z"
  else
    command date "$@"
  fi
}
export -f date

# Override file existence checks for default paths
# This allows tests to verify default behavior without creating root files
_original_test="$(command -v test)"
test() {
  # If checking default SSH paths, pretend they exist
  if [[ "$1" == "-f" ]] && [[ "$2" == "/id_rsa" || "$2" == "/known_hosts" ]]; then
    return 0
  fi
  command test "$@"
}
export -f test

# Also override [[ -f ... ]] checks via a wrapper
# This is trickier since [[ ]] is a shell builtin, but we can intercept the validation
# Actually, let's just create the files in setup
