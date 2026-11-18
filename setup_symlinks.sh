#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBSMB2_DIR="$SCRIPT_DIR/libsmb2"

if [ ! -d "$LIBSMB2_DIR/lib" ]; then
    echo "Error: $LIBSMB2_DIR/lib not found. Run: git submodule update --init"
    exit 1
fi

create_lib_symlinks() {
    local platform_dir="$1"
    local lib_dir="$platform_dir/libsmb2_lib"

    rm -rf "$lib_dir"
    mkdir -p "$lib_dir"

    for f in "$LIBSMB2_DIR"/lib/*.c "$LIBSMB2_DIR"/lib/*.h; do
        [ -f "$f" ] || continue
        ln -sf "$(python3 -c "import os; print(os.path.relpath('$f', '$lib_dir'))")" "$lib_dir/$(basename "$f")"
    done

    echo "Created $(ls "$lib_dir" | wc -l | tr -d ' ') symlinks in $lib_dir"

    ln -sfn "$LIBSMB2_DIR" "$platform_dir/libsmb2"
    echo "Created directory symlink $platform_dir/libsmb2 -> $LIBSMB2_DIR"
}

create_lib_symlinks "$SCRIPT_DIR/macos"
create_lib_symlinks "$SCRIPT_DIR/ios"
