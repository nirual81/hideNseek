#!/usr/bin/env python3
"""Run the portable probe check and inspect Seeker's .deb or --ipa package."""
import argparse
import io
import pathlib
import plistlib
import re
import struct
import subprocess
import tarfile
import zipfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--ipa", action="store_true", help="check the sideload archive instead of the rootless .deb")
args = parser.parse_args()

root = pathlib.Path(__file__).resolve().parent.parent
check = root / "dev/.check"
check.mkdir(exist_ok=True)
subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(root / "dev/check.c"), "-o", str(check / "check")], check=True)
subprocess.run([str(check / "check")], check=True)
subprocess.run(["bash", "-n", str(root / "dev/setup.sh")], check=True)

suffix = ".ipa" if args.ipa else "_iphoneos-arm64.deb"
package = root / f"seeker/packages/com.hidenseek.seeker_0.1.0{suffix}"
assert package.is_file(), "Build first: make -C seeker package" + (" PACKAGE_FORMAT=ipa" if args.ipa else "")
def member(name):
    return subprocess.check_output(["ar", "p", str(package), name])

if args.ipa:
    with zipfile.ZipFile(package) as archive:
        assert archive.testzip() is None, "Damaged IPA archive"
        files = {entry.filename: entry for entry in archive.infolist() if not entry.is_dir()}
        prefix = "Payload/Seeker.app/"
        assert set(files) == {prefix + "Info.plist", prefix + "Seeker"}, "Unexpected IPA payload or stale archive member"
        assert len(archive.namelist()) == len(set(archive.namelist())), "Duplicate archive members"
        info = plistlib.loads(archive.read(prefix + "Info.plist"))
        assert (files[prefix + "Seeker"].external_attr >> 16) & 0o777 == 0o755
        binary = archive.read(prefix + "Seeker")
else:
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
        assert files[prefix + "Seeker"].mode == 0o755
        binary = archive.extractfile(files[prefix + "Seeker"]).read()

assert info["MinimumOSVersion"] == "18.0.1"
assert info["CFBundleIdentifier"] == "com.hidenseek.seeker"
assert info["CFBundleExecutable"] == "Seeker" and info["CFBundlePackageType"] == "APPL"
assert set(info["LSApplicationQueriesSchemes"]) == {"sileo", "zbra", "filza", "dopamine"}
assert struct.unpack_from("<II", binary) == (0xFEEDFACF, 0x0100000C), "Expected thin arm64 Mach-O"
executable = check / ("Seeker-ipa" if args.ipa else "Seeker")
executable.write_bytes(binary)

tools = root / "dev/theos/toolchain/linux/iphone/bin"
commands = subprocess.check_output([str(tools / "otool"), "-l", str(executable)], text=True)
assert re.search(r"minos\s+18\.0\.1\b", commands), "Wrong binary deployment target"
assert "LC_CODE_SIGNATURE" in commands
assert "LC_MAIN" in commands
linked = subprocess.check_output([str(tools / "otool"), "-L", str(executable)], text=True)
for line in linked.splitlines()[1:]:
    assert line.strip().startswith(("/usr/lib/", "/System/Library/")), "Unexpected runtime dependency"
raw_entitlements = subprocess.check_output([str(tools / "ldid"), "-e", str(executable)])
entitlements = plistlib.loads(raw_entitlements) if raw_entitlements.strip() else {}
if args.ipa:
    assert not entitlements, "IPA must not request the jailbreak build's private entitlements"
    assert "/var/jb" not in commands, "IPA must not have rootless load paths"
    print(f"IPA passed: Payload layout, archive CRCs, executable mode, arm64, iOS 18.0.1, no entitlements, system libraries ({package.stat().st_size:,} bytes). Needs signing/provisioning before sideloading.")
else:
    assert entitlements == plistlib.loads((root / "seeker/entitlements.plist").read_bytes())
    assert entitlements["com.apple.private.security.container-required"] is True
    print(f"Package passed: arm64, iOS 18.0.1, rootless paths, ownership, scripts, entitlements, system libraries ({package.stat().st_size:,} bytes).")
print("These are host checks. Device launch and detection behavior still require iOS 18.0.1 hardware.")
