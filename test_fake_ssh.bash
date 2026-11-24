# Starts a real process with argv[0] "ssh" and "grep" in its argv, like the PROXY_PROTOCOL session
start_fake_ssh() {
  cp "$(command -v bash)" "${BATS_TEST_TMPDIR}/ssh"
  PATH="${BATS_TEST_TMPDIR}:${PATH}" ssh -c 'command sleep 60; :' grep &
  FAKE_SSH_PID=$!
  export FAKE_SSH_PID
}

stop_fake_ssh() {
  kill "${FAKE_SSH_PID}" 2>/dev/null || true
}
