# Starts a real process named "ssh" whose argv contains "grep", like the PROXY_PROTOCOL session
start_fake_ssh() {
  cp "$(command -v bash)" "${BATS_TEST_TMPDIR}/ssh"
  "${BATS_TEST_TMPDIR}/ssh" -c 'command sleep 60; :' grep &
  FAKE_SSH_PID=$!
  export FAKE_SSH_PID
}

stop_fake_ssh() {
  kill "${FAKE_SSH_PID}" 2>/dev/null || true
}
