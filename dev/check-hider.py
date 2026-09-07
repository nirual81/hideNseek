#!/usr/bin/env python3
"""Check Hider's shared path policy and the actual rootless package."""
import hashlib
import io
import pathlib
import plistlib
import struct
import subprocess
import tarfile

root = pathlib.Path(__file__).resolve().parent.parent
check = root / "dev/.check"
check.mkdir(exist_ok=True)
subprocess.run(["cc", "-std=c11", "-Wall", "-Wextra", "-Werror", str(root / "dev/check-hider.c"), "-o", str(check / "check-hider")], check=True)
subprocess.run([str(check / "check-hider")], check=True)
for script in ("dev/setup.sh", "dev/hider-clang.sh", "hider/layout/DEBIAN/postinst"):
    subprocess.run(["bash", "-n", str(root / script)], check=True)

version = next(line.split(": ", 1)[1] for line in (root / "hider/control").read_text().splitlines() if line.startswith("Version: "))
package = root / f"hider/packages/com.hidenseek.hider_{version}_iphoneos-arm64.deb"
assert package.is_file(), "Build first: make -C hider package"
def member(name):
    return subprocess.check_output(["ar", "p", str(package), name])

assert member("debian-binary") == b"2.0\n"
with tarfile.open(fileobj=io.BytesIO(member("control.tar.gz"))) as archive:
    files = {entry.name.removeprefix("./"): entry for entry in archive.getmembers()}
    control = archive.extractfile(files["control"]).read().decode()
    assert "Package: com.hidenseek.hider\n" in control
    assert f"Version: {version}\n" in control
    assert "Architecture: iphoneos-arm64\n" in control
    assert "Depends: firmware (>= 18.0.1), ellekit, preferenceloader\n" in control
    script = files["postinst"]
    assert script.mode == 0o755 and script.uid == script.gid == 0
    assert archive.extractfile(script).read() == (root / "hider/layout/DEBIAN/postinst").read_bytes()

with tarfile.open(fileobj=io.BytesIO(member("data.tar.xz"))) as archive:
    files = {entry.name.removeprefix("./"): entry for entry in archive.getmembers() if entry.isfile()}
    prefix = "var/jb/"
    expected = {
        "usr/lib/TweakInject/Hider.dylib", "usr/lib/TweakInject/Hider.plist",
        "Library/PreferenceBundles/HiderPrefs.bundle/HiderPrefs",
        "Library/PreferenceBundles/HiderPrefs.bundle/Info.plist",
        "Library/PreferenceLoader/Preferences/Hider.plist",
    }
    assert set(files) == {prefix + name for name in expected}
    assert all(entry.uid == entry.gid == 0 for entry in files.values())
    payload = {name.removeprefix(prefix): archive.extractfile(entry).read() for name, entry in files.items()}
    info = plistlib.loads(payload["Library/PreferenceBundles/HiderPrefs.bundle/Info.plist"])
    assert info["MinimumOSVersion"] == "18.0.1"
    assert info["CFBundleShortVersionString"] == version
    assert info["NSPrincipalClass"] == "HSSettingsController"
    assert info["CFBundleIdentifier"] == "com.hidenseek.hider.preferences"
    entry = plistlib.loads(payload["Library/PreferenceLoader/Preferences/Hider.plist"])["entry"]
    assert entry["bundle"] == "HiderPrefs" and entry["detail"] == info["NSPrincipalClass"]
    assert plistlib.loads(payload["usr/lib/TweakInject/Hider.plist"]) == {"Filter": {"Bundles": ["com.apple.UIKit"]}}

def verify_signature(binary, signature):
    magic, length, count = struct.unpack_from(">III", signature)
    assert magic == 0xFADE0CC0 and length <= len(signature)
    directories = 0
    for index in range(count):
        _, offset = struct.unpack_from(">II", signature, 12 + index * 8)
        if struct.unpack_from(">I", signature, offset)[0] != 0xFADE0C02:
            continue
        cd = signature[offset:]
        _, _, _, _, hash_offset, _, _, slots, limit = struct.unpack_from(">9I", cd)
        size, kind, _, page_power = struct.unpack_from("4B", cd, 36)
        assert kind in (1, 2, 3, 4) and limit <= len(binary)
        algorithm = {1: "sha1", 2: "sha256", 3: "sha256", 4: "sha384"}[kind]
        page = 1 << page_power
        assert slots == (limit + page - 1) // page
        for slot in range(slots):
            digest = hashlib.new(algorithm, binary[slot * page:min((slot + 1) * page, limit)]).digest()[:size]
            assert digest == cd[hash_offset + slot * size:hash_offset + (slot + 1) * size], "Invalid code signature"
        directories += 1
    assert directories

def verify_auth(pointer, discriminator):
    # dyld arm64e authenticated pointer: DA key, address diversity and type salt.
    assert pointer >> 63 == 1 and (pointer >> 49) & 3 == 2 and (pointer >> 48) & 1 == 1
    assert (pointer >> 32) & 0xFFFF == discriminator, f"Missing pointer authentication discriminator {discriminator:#x}"

tools = root / "dev/theos/toolchain/linux/iphone/bin"
for name in ("usr/lib/TweakInject/Hider.dylib", "Library/PreferenceBundles/HiderPrefs.bundle/HiderPrefs"):
    fat = payload[name]
    magic, count = struct.unpack_from(">II", fat)
    assert magic == 0xCAFEBABE and count == 2
    architectures = set()
    for index in range(count):
        cpu, subtype, offset, size, _ = struct.unpack_from(">5I", fat, 8 + index * 20)
        assert cpu == 0x100000C and offset + size <= len(fat)
        raw_subtype = subtype
        subtype &= 0xFFFFFF
        architectures.add(subtype)
        binary = fat[offset:offset + size]
        header = struct.unpack_from("<8I", binary)
        assert header[0] == 0xFEEDFACF and header[1] == cpu
        if subtype == 2:
            assert raw_subtype == header[2] == 0x80000002, "Legacy/unversioned arm64e ABI; rebuild with the native-ABI compiler, not allemande"
        position = 32
        minimum = signed = classes = strings = False
        for _ in range(header[4]):
            command, length = struct.unpack_from("<II", binary, position)
            assert length >= 8 and position + length <= len(binary)
            if command == 0x32:  # LC_BUILD_VERSION
                platform, minimum_os = struct.unpack_from("<II", binary, position + 8)
                assert platform == 2 and minimum_os == (18 << 16 | 1)
                minimum = True
            if command == 0x1D:  # LC_CODE_SIGNATURE
                start, length_sig = struct.unpack_from("<II", binary, position + 8)
                verify_signature(binary, binary[start:start + length_sig])
                signed = True
            if command == 0x19 and subtype == 2:  # LC_SEGMENT_64
                sections = struct.unpack_from("<I", binary, position + 64)[0]
                for section in range(sections):
                    at = position + 72 + section * 80
                    section_name = binary[at:at + 16].split(b"\0")[0]
                    section_size, file_offset = struct.unpack_from("<QI", binary, at + 40)
                    if section_name == b"__objc_data":
                        assert section_size and section_size % 40 == 0
                        for at in range(file_offset, file_offset + section_size, 40):
                            isa, superclass = struct.unpack_from("<QQ", binary, at)
                            verify_auth(isa, 0x6AE1)
                            verify_auth(superclass, 0xB5AB)
                            ro_pointer = struct.unpack_from("<Q", binary, at + 32)[0]
                            verify_auth(ro_pointer, 0x61F8)
                        classes = True
                    if section_name == b"__cfstring":
                        assert section_size and section_size % 32 == 0
                        for at in range(file_offset, file_offset + section_size, 32):
                            isa = struct.unpack_from("<Q", binary, at)[0]
                            verify_auth(isa, 0x6AE1)
                        strings = True
            position += length
        assert minimum and signed
        if subtype == 2:
            assert classes and strings, "Expected native authenticated Objective-C / CFString data"
    assert architectures == {0, 2}
    output = check / pathlib.Path(name).name
    output.write_bytes(fat)
    linked = subprocess.check_output([str(tools / "otool"), "-L", str(output)], text=True)
    for line in linked.splitlines():
        if not line.startswith("\t"):
            continue
        if line.strip().startswith("/var/jb/Library/PreferenceBundles/HiderPrefs.bundle/HiderPrefs ("):
            continue  # This bundle's own LC_ID_DYLIB, not a dependency.
        assert line.strip().startswith(("/usr/lib/", "/System/Library/", "@rpath/Hider.dylib", "@rpath/CydiaSubstrate.framework/")), line
    commands = subprocess.check_output([str(tools / "otool"), "-l", str(output)], text=True)
    assert "/var/jb/Library/Frameworks" in commands and "/var/jb/usr/lib" in commands
    assert "Swift" not in linked and "oldabi" not in linked
    if name.endswith("Hider.dylib"):
        assert "@rpath/CydiaSubstrate.framework/CydiaSubstrate" in linked
        for marker in (f"Hider {version} diagnostic", "Hider-startup-XXXXXX", "c/before", "objc/before", "access-var-jb", "main-queue/reached"):
            assert marker.encode() in fat, f"Missing startup trace marker: {marker}"

print(f"Hider {version} package passed: arm64 + native arm64e ABI, authenticated class RO metadata, iOS 18.0.1, rootless layout, Settings entry, dependencies and signature page hashes ({package.stat().st_size:,} bytes).")
print("User confirmed Settings loads in 0.1.1; selected-app crashes remain unresolved. This diagnostic build needs a device trace.")
