#!/usr/bin/env bash
# smoke-wp.sh <base-image-ref>
#
# Builds a throwaway consumer on top of wp-base and asserts the container
# actually serves PHP through nginx and php-fpm. Also asserts the conf.d
# override path works, since that is what lets projects drop their 1700-line
# php.ini copies.
set -euo pipefail

BASE_IMAGE="${1:-wp-base:test}"
CONTAINER="wp-base-smoke-$$"
PORT="${SMOKE_PORT:-18080}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cleanup() { docker rm -f "$CONTAINER" >/dev/null 2>&1 || true; }
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }

echo "==> building consumer on ${BASE_IMAGE}"
docker build -q --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
    -t "${CONTAINER}:img" "${HERE}/fixtures" >/dev/null

echo "==> starting container"
docker run -d --name "$CONTAINER" -p "${PORT}:80" "${CONTAINER}:img" >/dev/null

echo "==> waiting for HTTP"
body=""
for _ in $(seq 1 30); do
    body="$(curl -fsS --max-time 2 "http://localhost:${PORT}/" 2>/dev/null || true)"
    [[ "$body" == *SMOKE-OK* ]] && break
    sleep 1
done

if [[ "$body" != *SMOKE-OK* ]]; then
    docker logs "$CONTAINER" 2>&1 | tail -30 >&2
    fail "container never served PHP"
fi

echo "    ${body}"

[[ "$body" == *"missing=none"* ]] || fail "extensions missing: ${body}"

# The base ships max_execution_time=600; the fixture's conf.d drop-in sets 900.
# Seeing 900 proves overrides land without replacing the whole php.ini.
[[ "$body" == *"max_exec=900"* ]] || fail "conf.d override did not apply: ${body}"

echo "==> checking supervisor owns both processes"
procs="$(docker exec "$CONTAINER" ps -o args 2>/dev/null || true)"
[[ "$procs" == *"nginx: master"* ]] || fail "nginx master not running"
[[ "$procs" == *"php-fpm: master"* ]] || fail "php-fpm master not running"

echo "PASS"
