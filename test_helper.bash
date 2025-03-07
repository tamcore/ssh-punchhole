# Mock SSH command for local testing (bypasses an actual SSH call)
ssh() {
  echo "ssh $*"
}
export -f ssh
