#!/usr/bin/env bash
set -euo pipefail

# Thin delegation to luam's shared build orchestrator
# (lib/static/build.lua), like brain-ex and daat: it owns gathering the
# sources, bundling and the final compile+link, so luam can reorganise
# its internals without breaking this script.

cd "$(dirname "$0")/.."

if [ -z "${LUAM_DIR:-}" ]; then
    LUAM_DIR=$(cd ../luam && pwd)
fi

if [ ! -f "$LUAM_DIR/obj/liblua.a" ]; then
    echo "Error: $LUAM_DIR/obj/liblua.a not found. Set LUAM_DIR to a built luam checkout." >&2
    exit 1
fi

exec "$LUAM_DIR/bin/luam" "$LUAM_DIR/lib/static/build.lua" \
    --entry main.lua \
    --bin camopass \
    --luamdir "$LUAM_DIR" \
    "$@"
