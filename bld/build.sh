#!/bin/bash
set -e

# Change to project root (one level up from bld/)
cd "$(dirname "$0")/.."

PROJECT="camopass"

# Resolve dependency paths (allow env overrides)
if [ -z "$LUAM_DIR" ]; then
    LUAM_DIR="$HOME/Projects/luam"
fi

if [ ! -f "$LUAM_DIR/src/lauxlib.h" ]; then
    echo "Error: LUAM_DIR not set or lauxlib.h not found at $LUAM_DIR." >&2
    exit 1
fi

# Include paths
INC_LUA="-I$LUAM_DIR/src"

# Lib paths
LIB_LUA="$LUAM_DIR/obj/liblua.a"

# System libs
LIBS="-ldl -lm"

echo "Preparing Luam sources..."
cp src/obfuscator.lua .

echo "Statically compiling native binary using luastatic..."
export CC=gcc
luam "$LUAM_DIR/lib/static/static.lua" entry.lua obfuscator.lua "$LIB_LUA" "$INC_LUA" $LIBS

echo "Finalizing binary..."
mkdir -p bin
mv entry bin/$PROJECT
chmod +x bin/$PROJECT

echo "Cleaning up intermediate files..."
rm -f obfuscator.lua entry.static.c

echo "Static compilation complete: bin/$PROJECT"
ls -la bin/$PROJECT
