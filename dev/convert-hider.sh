#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ $# == 1 && -d $1 ]] || { echo 'Expected the Theos staging directory.' >&2; exit 1; }
[[ -x allemande/allemande ]] || { echo 'Run bash dev/setup.sh first.' >&2; exit 1; }
for binary in "$1/usr/lib/TweakInject/Hider.dylib" "$1/Library/PreferenceBundles/HiderPrefs.bundle/HiderPrefs"; do
    [[ -f $binary ]] || { echo "Missing binary: $binary" >&2; exit 1; }
    # Convert only staged copies, then replace the now-invalid ad hoc signature.
    allemande/allemande "$binary"
    theos/toolchain/linux/iphone/bin/ldid -s "$binary"
    theos/toolchain/linux/iphone/bin/ldid -S "$binary"
done
