# test/helpers/md-view-server.bash — run bin/md-view-server for a test.
#
# The server reads MD_VIEW_DIR and MD_VIEW_PORT from the environment, so a
# test exports both before start_server. stop_server belongs in teardown.

MD_VIEW_SERVER="$REPO_DIR/bin/md-view-server"
SERVER_PID=""

# A port nothing listens on: bound once to learn the number, then released.
free_port() {
  python3 -c 'import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])'
}

# req <curl args>: never through a proxy, and never left hanging.
req() { curl -s --noproxy '*' --max-time 5 "$@"; }

# expect <status> <curl args>: the request must be answered with that status.
expect() {
  local want="$1" got
  shift
  got="$(req -o /dev/null -w '%{http_code}' "$@")" || true
  [ "$got" = "$want" ] || {
    echo "expected $want, got $got: $*"
    return 1
  }
}

# Any HTTP answer means the server is up. fd 3 is closed for it: bats waits
# on every process that still holds that descriptor.
start_server() {
  "$MD_VIEW_SERVER" > "$TEST_TMPDIR/server.log" 2>&1 3>&- &
  SERVER_PID=$!
  local _
  for _ in $(seq 50); do
    req --max-time 1 -o /dev/null "http://127.0.0.1:$MD_VIEW_PORT/" && return 0
    kill -0 "$SERVER_PID" 2>/dev/null || break
    sleep 0.1
  done
  # Show why, or a CI-only failure leaves nothing to go on.
  {
    echo "md-view-server did not start on port $MD_VIEW_PORT"
    cat "$TEST_TMPDIR/server.log"
  } >&2
  return 1
}

# Safe to call mid-test as well as in teardown: the killed server's status
# (143) must not count as the test's own failure.
stop_server() {
  [ -n "$SERVER_PID" ] || return 0
  kill "$SERVER_PID" 2>/dev/null || true
  wait "$SERVER_PID" 2>/dev/null || true # reap so bash prints no "Terminated"
  SERVER_PID=""
}
