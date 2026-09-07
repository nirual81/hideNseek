#!/usr/bin/env python3
"""Run the portable probe check and inspect the actual Debian package."""
import io
import pathlib
import plistlib
import re
import struct
import subprocess
import tarfile

root = pathlib.Path(__file__).resolve().parent.parent
check = root / "dev/.check"
check.mkdir(exist_ok=True)
subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(root / "dev/check.c"), "-o", str(check / "check")], check=True)
subprocess.run([str(check / "check")], check=True)
subprocess.run(["bash", "-n", str(root / "dev/setup.sh")], check=True)

package = root / "seeker/packages/com.hidenseek.seeker_0.1.0_iphoneos-arm64.deb"
assert package.is_file(), "Build first: make -C seeker package"
def member(name):
    return subprocess.check_output(["ar", "p", str(package), name])

assert member("debian-binary") == b"2.0\n"
with tarfile.open(fileobj=io.BytesIO(member("control.tar.gz"))) as archive:
    files = {entry.name.removeprefix("./"): entry for entry in archive.getmembers()}
    control = archive.extractfile(files["control"]).read().decode()
    assert "Architecture: iphoneos-arm64\n" in control
    assert "Depends: firmware (>= 18.0.1), uikittools\n" in control
    assert "Package: com.hidenseek.seeker\n" in control
    for name in ("postinst", "postrm"):
        entry = files[name]
        assert entry.mode == 0o755 and entry.uid == entry.gid == 0
        script = archive.extractfile(entry).read()
        subprocess.run(["sh", "-n"], input=script, check=True)
        assert b"/var/jb/Applications/Seeker.app" in script

with tarfile.open(fileobj=io.BytesIO(member("data.tar.xz"))) as archive:
    files = {entry.name.removeprefix("./"): entry for entry in archive.getmembers() if entry.isfile()}
    assert files and all(name.startswith("var/jb/Applications/Seeker.app/") for name in files)
    assert all(entry.uid == entry.gid == 0 for entry in files.values())
    prefix = "var/jb/Applications/Seeker.app/"
    info = plistlib.loads(archive.extractfile(files[prefix + "Info.plist"]).read())
    assert info["MinimumOSVersion"] == "18.0.1"
    assert info["CFBundleIdentifier"] == "com.hidenseek.seeker"
    assert set(info["LSApplicationQueriesSchemes"]) == {"sileo", "zbra", "filza", "dopamine"}
    entry = files[prefix + "Seeker"]
    assert entry.mode == 0o755
    binary = archive.extractfile(entry).read()
    assert struct.unpack_from("<II", binary) == (0xFEEDFACF, 0x0100000C), "Expected thin arm64 Mach-O"
    executable = check / "Seeker"
    executable.write_bytes(binary)

tools = root / "dev/theos/toolchain/linux/iphone/bin"
commands = subprocess.check_output([str(tools / "otool"), "-l", str(executable)], text=True)
assert re.search(r"minos\s+18\.0\.1\b", commands), "Wrong binary deployment target"
assert "LC_CODE_SIGNATURE" in commands
assert "LC_MAIN" in commands
linked = subprocess.check_output([str(tools / "otool"), "-L", str(executable)], text=True)
for line in linked.splitlines()[1:]:
    assert line.strip().startswith(("/usr/lib/", "/System/Library/")), "Unexpected runtime dependency"
entitlements = plistlib.loads(subprocess.check_output([str(tools / "ldid"), "-e", str(executable)]))
assert entitlements == plistlib.loads((root / "seeker/entitlements.plist").read_bytes())
assert entitlements["com.apple.private.security.container-required"] is True
print(f"Package passed: arm64, iOS 18.0.1, rootless paths, ownership, scripts, entitlements, system libraries ({package.stat().st_size:,} bytes).")
print("These are host checks. Device launch and detection behavior still require iOS 18.0.1 hardware.")
