#!/usr/bin/env bash
# Tests for pub_version.sh against a local stand-in for the pub.dev API.
# Run: bash tool/release/pub_version_test.sh
set -uo pipefail

script="$(cd "$(dirname "$0")" && pwd)/pub_version.sh"
work="$(mktemp -d)"
failures=0

fail() {
  echo "FAIL: $*"
  failures=$((failures + 1))
}

# The stand-in answers GET <path> from routes.json ({"<path>": [status, body]})
# and 404s anything else. It re-reads the file on every request, so a test can
# change what the "registry" holds while a poll is running.
cat > "$work/stub.py" <<'PY'
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

routes_file, port_file = sys.argv[1], sys.argv[2]

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        with open(routes_file) as f:
            routes = json.load(f)
        status, body = routes.get(self.path, [404, {"error": {"code": "NotFound"}}])
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass

server = HTTPServer(("127.0.0.1", 0), Handler)
with open(port_file, "w") as f:
    f.write(str(server.server_port))
server.serve_forever()
PY

echo '{}' > "$work/routes.json"
python3 -I "$work/stub.py" "$work/routes.json" "$work/port" &
stub_pid=$!
disown "$stub_pid"
trap 'kill "$stub_pid" 2>/dev/null; rm -rf "$work"' EXIT
for _ in $(seq 50); do [[ -s "$work/port" ]] && break; sleep 0.1; done
PUB_HOSTED_URL="http://127.0.0.1:$(cat "$work/port")"
export PUB_HOSTED_URL

registry_has() {
  # registry_has <path> <status> <json body>
  python3 -I -c 'import json,sys; r=json.load(open(sys.argv[1])); r[sys.argv[2]]=[int(sys.argv[3]), json.loads(sys.argv[4])]; json.dump(r, open(sys.argv[1], "w"))' \
    "$work/routes.json" "$1" "$2" "$3"
}

# --- status: a version pub.dev serves is "published". ---
registry_has /api/packages/formbricks/versions/1.3.1 200 '{"version": "1.3.1"}'
out="$(bash "$script" status formbricks 1.3.1 2> "$work/err")" || fail "status of a published version exited non-zero: $(cat "$work/err")"
[[ "$out" == "published" ]] || fail "status of a published version: expected 'published', got '$out'"

# --- status: a version pub.dev 404s is "missing", so the publish goes ahead. ---
out="$(bash "$script" status formbricks 1.4.0 2> "$work/err")" || fail "status of a missing version exited non-zero: $(cat "$work/err")"
[[ "$out" == "missing" ]] || fail "status of a missing version: expected 'missing', got '$out'"

# --- status: an outage fails the run instead of looking like "missing". ---
registry_has /api/packages/formbricks/versions/1.5.0 503 '{"error": "unavailable"}'
out="$(bash "$script" status formbricks 1.5.0 2> /dev/null)"
code=$?
[[ $code -eq 2 ]] || fail "status during an outage: expected exit 2, got $code (output '$out')"

# --- status: build metadata is URL-encoded, a raw "+" would be read as a space. ---
registry_has /api/packages/formbricks/versions/1.4.0%2Bbuild.5 200 '{"version": "1.4.0+build.5"}'
out="$(bash "$script" status formbricks 1.4.0+build.5 2> "$work/err")" || fail "status of a +build version exited non-zero: $(cat "$work/err")"
[[ "$out" == "published" ]] || fail "status of a +build version: expected 'published', got '$out'"

# --- wait: returns once pub.dev serves the version, riding out an outage. ---
export PUB_WAIT_INTERVAL=1
registry_has /api/packages/formbricks/versions/1.6.0 503 '{"error": "unavailable"}'
(sleep 2 && registry_has /api/packages/formbricks/versions/1.6.0 200 '{"version": "1.6.0"}') &
PUB_WAIT_TIMEOUT=20 bash "$script" wait formbricks 1.6.0 > "$work/out" 2>&1 ||
  fail "wait for a version that appears mid-poll exited non-zero: $(cat "$work/out")"
wait

# --- wait: fails once the timeout passes without the version. ---
started=$SECONDS
if PUB_WAIT_TIMEOUT=2 bash "$script" wait formbricks 9.9.9 > "$work/out" 2>&1; then
  fail "wait for a version that never appears exited zero"
fi
grep -q '::error::' "$work/out" || fail "wait timeout did not print a GitHub error annotation: $(cat "$work/out")"
((SECONDS - started <= 10)) || fail "wait ignored its timeout (took $((SECONDS - started))s)"

if [[ $failures -gt 0 ]]; then
  echo "$failures failure(s)"
  exit 1
fi
echo "pub_version: all tests passed"
