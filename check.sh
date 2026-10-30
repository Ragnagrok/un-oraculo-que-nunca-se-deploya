#!/usr/bin/env bash
# Replays the story of the article on a copy of the app:
#   1. the model and the app disagree about reversing on an expired card;
#   2. after deciding that, they disagree about reversing twice;
#   3. after fixing that, 1000 random sequences agree.
set -euo pipefail
cd "$(dirname "$0")"

port=${PORT:-8080}
work=$(mktemp -d)
trap 'kill $server 2>/dev/null || true; rm -rf "$work"' EXIT

cp -r app "$work/app"

# Restarted after each patch, so that no cache serves the old code.
start() {
  php -S "localhost:$port" "$work/app/index.php" >/dev/null 2>&1 &
  server=$!
  until curl -s "localhost:$port/reset" >/dev/null; do :; done
}
stop() { kill $server; wait $server 2>/dev/null || true; }
start

cabal build --enable-tests lockstep >/dev/null

run() { SUT="http://localhost:$port" cabal test --test-show-details=direct 2>&1 || true; }

expect() {
  local out
  out=$(run)
  if grep -qF -- "$1" <<<"$out"; then
    echo "ok: $1"
  else
    echo "FAILED: expected '$1', got:"
    echo "$out"
    exit 1
  fi
}

expect '[Sell 1,Expire,Reverse]'
stop; patch -s -p1 -d "$work" < fixes/1-expired-cards.diff; start
expect '[Sell 1,Redeem 1,Reverse,Reverse]'
stop; patch -s -p1 -d "$work" < fixes/2-double-reverse.diff; start
expect '+++ OK, passed 1000 tests.'
