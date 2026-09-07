#!/usr/bin/env bash
set -euo pipefail
# Reuse the installed compiler; do not fall back to Theos's legacy Clang 11.
compiler=${HIDER_CLANG:-/usr/bin/clang}
[[ $compiler == /* && -x $compiler ]] || { echo 'Set HIDER_CLANG to an absolute Clang 22 executable path.' >&2; exit 1; }
case "$("$compiler" -dumpversion)" in
    22.*) ;;
    *) echo 'Hider requires Clang 22 for native arm64e metadata; see README.md.' >&2; exit 1 ;;
esac
exec "$compiler" "$@"
