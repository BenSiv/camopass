#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if [ -z "${LUAM_DIR:-}" ]; then
    LUAM_DIR=$(cd ../luam && pwd)
fi

echo "Building bin/camopass"
LUAM_DIR="$LUAM_DIR" ./bld/build.sh

export PATH="${LUAM_DIR}/bin:${PATH}"
export LUA_PATH="./src/?.lua;${LUAM_DIR}/lib/?.lua;${LUAM_DIR}/lib/?/init.lua;;"
export LUA_CPATH="${LUAM_DIR}/lib/?.so;${LUAM_DIR}/lib/?/?.so;${LUAM_DIR}/bin/?.so;;"
export CAMOPASS_BIN="$(pwd)/bin/camopass"

echo "Running core obfuscator tests"
"$LUAM_DIR/bin/luam" tst/test_obfuscator.lua

echo "Running CLI integration tests against $CAMOPASS_BIN"
"$LUAM_DIR/bin/luam" tst/test_cli.lua
