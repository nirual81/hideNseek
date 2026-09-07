# Seeker

Seeker shows which local jailbreak detections fire, with the evidence from each check. It is a small Objective-C/UIKit app for **iOS 18.0.1 or later**, packaged as a rootless `.deb` for Dopamine 3 and Sileo.

Open the app to run a scan. **Fired** shows findings; **All checks** also shows checks with no observed signal and checks that were unavailable. Tap refresh or pull down to rerun. Results stay in memory. The app has no backend or telemetry.

## Build on Linux

The setup script supports x86_64 Linux and installs tools inside `dev/`. It downloads pinned versions of Theos, the Linux iOS toolchain and the patched iOS SDK, and checks the archive hashes. It does not change shell profiles or install system packages.

On this project's original Arch/Omarchy host, all host prerequisites were already installed. On a new machine, install missing prerequisites using your package manager:

```sh
# Arch / Omarchy, only if needed:
sudo pacman -S --needed base-devel git curl perl rsync fakeroot xz python libbsd openssl ncurses

# Debian / Ubuntu alternative:
sudo apt install build-essential git curl perl rsync fakeroot xz-utils python3 libbsd0 libtinfo6 libuuid1 zlib1g
```

Run from the project root (the verification script requires Python 3.9 or later):

```sh
bash dev/setup.sh
make -C seeker package
python3 dev/check.py
```

Output: `seeker/packages/com.hidenseek.seeker_0.1.0_iphoneos-arm64.deb`.

The build uses Clang 11.1.0 and SDK 16.5 for existing native APIs, with the binary deployment target, app metadata and package dependency set to **18.0.1**. SDK version and minimum runtime version are separate. The package contains an arm64 executable, which also runs on supported arm64e devices. Exact tool versions, hashes and local setup facts are in [AGENTS.md](AGENTS.md).

`python3 dev/check.py` exercises presence/error classification and filesystem consistency with real files and a dangling symlink. It also inspects the built package's architecture, minimum OS, paths, ownership, scripts, embedded entitlements and linked libraries. It cannot run UIKit on Linux.

To rebuild everything:

```sh
make -C seeker clean
make -C seeker package
python3 dev/check.py
```

## Install on iOS 18.0.1

The device must already have an active, supported Dopamine 3 jailbreak and Sileo. Dopamine's iOS 18 hardware support is narrower than all arm64e devices; check the [upstream compatibility information](https://github.com/opa334/Dopamine/tree/3.x) for your device.

Transfer the `.deb` to the device. Open it in Sileo using the file/share menu and install Seeker. If your file app does not offer Sileo for local packages, use the SSH method below. The package registers its Home Screen app with `uicache` during installation. Open **Seeker** to scan.

For SSH installation, use your device's SSH user, address and configured port. The following example uses port 22 and the `mobile` account:

```sh
scp seeker/packages/com.hidenseek.seeker_0.1.0_iphoneos-arm64.deb mobile@IPHONE_IP:/var/mobile/
ssh mobile@IPHONE_IP
```

Then run on the device, using its configured administrative authentication:

```sh
sudo /var/jb/usr/bin/dpkg -i /var/mobile/com.hidenseek.seeker_0.1.0_iphoneos-arm64.deb
```

If `dpkg` reports a missing dependency, install `uikittools` in Sileo and rerun the command. The installed bundle is `/var/jb/Applications/Seeker.app`. If its icon does not appear, run:

```sh
sudo /var/jb/usr/bin/uicache -p /var/jb/Applications/Seeker.app
```

Remove Seeker in Sileo, or run:

```sh
sudo /var/jb/usr/bin/dpkg -r com.hidenseek.seeker
```

No device was connected during development. The cross-build and host checks are verified separately from installation and runtime behavior.

## Detections

These checks implement the 11 surfaces in [DETECTION.md](DETECTION.md). A result is **FIRED**, **NOT OBSERVED**, or **UNAVAILABLE**. If a check finds something but also encounters blocked paths, it stays FIRED and includes the errors in its evidence.

| Surface | Implemented observations |
| --- | --- |
| Filesystem | 21 artifact paths through Foundation metadata, `stat`, `lstat`, `access`, and `open`; `/var` enumeration; comparable API consistency; root mount flags through `statfs` and `statvfs` |
| Symlinks | `/var/jb` link destination and resolved path |
| App discovery | Sileo, Zebra, Filza and Dopamine URL handlers; guarded LaunchServices bundle-ID lookup; app bundle paths in the filesystem checks |
| Loaded images | Current-process dyld image paths for bootstrap, injection, tweak and bypass components; main executable excluded |
| Objective-C runtime | Registered class names, the Shadow class/selector pair, origins of six C functions and `NSFileManager`'s `fileExistsAtPath:` implementation |
| Sandbox behavior | Unique temporary file creation/write attempts under `/private`, `/var/mobile`, `/var/jb`; opening Safari's directory without reading its contents |
| Process behavior | `fork()` success, immediate child exit and reaping |
| Debug state | `P_TRACED` and sampled task exception handlers |
| Instrumentation | Frida/Cycript modules, loopback ports 27042/27043, executable regions with write permission or the JavaScript JIT tag |
| Code signing | Current-process `csops` flags; sampled entitlements through SecTask; main executable `__TEXT,__text` bytes compared with disk |
| Environment and IPC | Injection variables, loopback SSH port 22, lookup of RocketBootstrap's two known service names |

The sandbox write probe creates only a UUID-named `.seeker-probe-*` file with exclusive creation and mode 0600. It immediately unlinks that file, writes one byte through its descriptor, then closes it. A cleanup failure is reported with the exact path. The fork child calls `_exit` without returning to UIKit. TCP probes connect only to `127.0.0.1`, wait at most 150 ms each for a connection, and send no payload. Mach probes look up services without sending service messages.

Seeker observes its own process. Its rootless package location and ad hoc signature are expected to fire checks. It requests an app container and has no platform, debugger, no-container or sandbox-bypass entitlement, but jailbreak launch behavior can still affect access. Running Seeker does not reproduce the sandbox or loaded code of another app.

The lists are heuristics. The memory scan stops after 8,192 regions and only flags RWX/JavaScript JIT executable regions. Method-origin checks do not detect every inline patch. The code comparison covers this thin arm64 executable's text section (up to 16 MiB), uses the local disk copy as its reference, and does not authenticate that reference. An app/icon database scan, kernel inspection, global process scan and debugger-blocking operations are not implemented. Dopamine uses launchd for its IPC, so RocketBootstrap service results are not a direct Dopamine daemon check. Private APIs can be absent or filtered, and a hiding layer can alter any of these observations.

On the device, confirm that the app opens, completes a scan, retains UNAVAILABLE results under All checks, and refreshes without freezing. Check known artifacts such as `/var/jb` against what the device exposes. The ad hoc signature row should explain that it is expected for this package. Compare with tweak injection enabled/disabled for Seeker if you want to inspect injection effects; no particular number of findings is guaranteed.

## Documentation sources

Research started with Context7's Theos and iOS Security Suite documentation. Context7 had no matching Dopamine documentation, and its snippets did not cover several low-level API and toolchain details. Those gaps were checked against upstream sources:

- [Theos rootless packaging](https://theos.dev/docs/rootless), [Linux installation](https://theos.dev/docs/installation-linux), and [installer source](https://github.com/theos/theos/blob/master/bin/install-theos)
- [iOS Security Suite](https://github.com/securing/IOSSecuritySuite)
- [Apple XNU code-signing flags](https://github.com/apple-oss-distributions/xnu/blob/main/osfmk/kern/cs_blobs.h)
- [Dopamine systemhook](https://github.com/opa334/Dopamine/blob/3.x/BaseBin/systemhook/src/main.c) and [IPC implementation](https://github.com/opa334/Dopamine/blob/3.x/BaseBin/libjailbreak/src/jbclient_xpc.c)
- [RocketBootstrap service definitions](https://github.com/rpetrich/RocketBootstrap/blob/master/rocketbootstrap_internal.h)

The app links only Apple's system libraries and frameworks. None of those research projects is an app dependency.
