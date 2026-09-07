#!/usr/bin/env bash
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")"
[[ $(uname -sm) == 'Linux x86_64' ]] || { echo 'Setup supports x86_64 Linux.' >&2; exit 1; }
for cmd in curl git make perl rsync fakeroot tar xz sha256sum python3 cc; do
    command -v "$cmd" >/dev/null || { echo "Missing host prerequisite: $cmd (see README.md)" >&2; exit 1; }
done
theos_commit=5280bd038207e14f8bd76f5417aa2fe641c03228
if [[ ! -d theos/.git ]]; then
    git clone --no-checkout https://github.com/theos/theos.git theos
    git -C theos checkout --detach "$theos_commit"
fi
[[ $(git -C theos rev-parse HEAD) == "$theos_commit" ]] || { echo 'Unexpected Theos revision; see AGENTS.md.' >&2; exit 1; }
git -C theos submodule update --init --recursive
mkdir -p downloads
download() {
    local url=$1 name=$2 digest=$3
    if [[ ! -f downloads/$name ]]; then
        curl -fL --retry 3 "$url" -o "downloads/$name.part"
        mv -- "downloads/$name.part" "downloads/$name"
    fi
    printf '%s  %s\n' "$digest" "downloads/$name" | sha256sum -c -
}
download https://github.com/L1ghtmann/llvm-project/releases/download/test-210562a/iOSToolchain-x86_64.tar.xz \
    iOSToolchain-x86_64.tar.xz a72a7a577e2fbe2838b6b5e9c72034fa7d114af96f0e1d4b016f18730ce4056e
download https://github.com/theos/sdks/releases/download/master-146e41f/iPhoneOS16.5.sdk.tar.xz \
    iPhoneOS16.5.sdk.tar.xz 5e0fd3f01266cce4ce012d4a99b38eb56578fca40d09edc81cd83dee958202fb
if [[ ! -f theos/toolchain/.seeker-ready ]]; then
    tar -xJf downloads/iOSToolchain-x86_64.tar.xz -C theos/toolchain
    touch theos/toolchain/.seeker-ready
fi
if [[ ! -f theos/sdks/.seeker-ready ]]; then
    tar -xJf downloads/iPhoneOS16.5.sdk.tar.xz -C theos/sdks
    touch theos/sdks/.seeker-ready
fi
theos/toolchain/linux/iphone/bin/clang --version
echo 'Ready. Build with: make -C seeker package'
