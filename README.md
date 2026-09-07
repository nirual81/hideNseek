# hideNseek

Two iOS 18.0.1 rootless packages: **Seeker** reports local jailbreak detections; **Hider** selectively hides known filesystem paths inside apps you choose. Source lives in `seeker/` and `hider/`; development tools stay in this project's `dev/` directory.

For the hiding tweak, see [Hider](#hider). The Seeker build and usage follow below.

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

The shared setup also checks for **Clang 22**, Hider's compiler. It was already installed on this host and is not downloaded by setup. See [Build Hider](#build-hider) to select its path. Seeker itself still uses the downloaded Clang 11 toolchain.

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

## Hider

Hider adds **Settings → Hider**, with a searchable list of system and user applications, including hidden app records returned by LaunchServices. Search by name or bundle ID, then tap an app to toggle its checkmark. All apps start disabled on a fresh install. **Disable all** clears the selection. Settings and SpringBoard remain visible in the list but cannot be enabled.

Close and reopen a selected app after changing its setting. Pull to refresh the installed-app list. Selections are saved locally; Hider has no daemon, network service or telemetry. Native UIKit supplies the search bar and accessible table cells. Ponytail ultra kept the picker free of an extra app-list dependency; only ElleKit and PreferenceLoader are required on the device.

### Build Hider

Use the Linux prerequisites above and **Clang 22** (tested with 22.1.8). `dev/hider-clang.sh` uses `/usr/bin/clang` by default and rejects other major versions. If Clang 22 is installed elsewhere, set its absolute path before setup and build, for example:

```sh
export HIDER_CLANG=/usr/bin/clang-22
```

Only set that override if the executable exists there. No new host package was needed on this project's machine. Run from the project root:

```sh
bash dev/setup.sh
make -C hider package
python3 dev/check-hider.py
```

Output: `hider/packages/com.hidenseek.hider_0.1.1_iphoneos-arm64.deb`.

Both the tweak and Settings bundle contain arm64 and arm64e slices, targeting iOS 18.0.1. Clang 22 emits native arm64e metadata. The build retains the project-local Theos SDK 16.5, ld64 linker and signing tools; it no longer uses allemande conversion or needs a system-wide `oldabi` package. The Makefile explicitly selects the cross-linker and new-ABI static libraries. DWARF 4 debug information keeps the bundled debug-symbol tool compatible. A clean build should produce no legacy-ABI or debug-attribute warnings.

The check compiles and runs the shared path policy against boundaries, dot components, aliases and real symlinks. It inspects both package slices, iOS minimums, Settings registration, dependencies, the versioned arm64e ABI header, authenticated Objective-C class read-only-data/isa/superclass and CFString pointers, and signed code-page hashes. These checks cannot verify injection or native Settings loading on Linux.

When upgrading the build tools from 0.1.0, run `make -C hider clean` before the build command to discard old objects. Install the `.deb`, not intermediate binaries from `.theos/obj`.

### Settings crash reported in 0.1.0

The reported device is an iPhone 11 Pro Max on iOS 18.0.1, Dopamine 3.0.9, ElleKit 1.2 and PreferenceLoader 2.2.8. Tapping Hider reportedly closes Settings before any transition, with no crash log found. Inspection of 0.1.0 found a legacy arm64e ABI header and unauthenticated class read-only-data pointers left by partial conversion. The earlier check missed those fields. Version 0.1.1 replaces that build path; the strengthened check rejects 0.1.0 and passes 0.1.1. The Settings source is unchanged. This is a build correction, not confirmation of the device crash's exact cause or a successful device retest.

### Install and recover

Use a supported device already running Dopamine 3 on iOS 18.0.1. Install its compatible rootless **ElleKit** (`ellekit`) and **PreferenceLoader** (`preferenceloader`) through Sileo. ElleKit provides injection and the Substrate-compatible hook API; PreferenceLoader loads the Settings page. Hider does not install or configure the jailbreak itself.

Transfer the `.deb` and install through Sileo where local-package opening is supported. Alternatively, using the same device-specific SSH settings as the Seeker instructions:

```sh
scp hider/packages/com.hidenseek.hider_0.1.1_iphoneos-arm64.deb mobile@IPHONE_IP:/var/mobile/
ssh mobile@IPHONE_IP
# On the device:
sudo /var/jb/usr/bin/dpkg -i /var/mobile/com.hidenseek.hider_0.1.1_iphoneos-arm64.deb
```

Install 0.1.1 over 0.1.0; saved selections remain intact. If dependencies are missing, install them in Sileo and rerun the device command. Complete any restart requested by Sileo, then **force-close Settings from the app switcher and reopen it** so it cannot reuse the old loaded bundle. Open **Hider**, select a test app and relaunch that app. If the page is missing, check PreferenceLoader and that injection is enabled for Settings. If hiding does not apply, check that Dopamine/Choicy or another injection manager allows Hider in that app. Disabling injection also disables Hider.

To recover from an app failing to launch, uncheck it in Settings or use **Disable all**, then relaunch it. To remove the tweak, use Sileo or SSH:

```sh
sudo /var/jb/usr/bin/dpkg -r com.hidenseek.hider
```

Restart affected apps after removal; already-loaded hooks cannot be removed by deleting the package. If Settings itself cannot open, use SSH removal or the jailbreak's no-tweak recovery mode. Hider requests no automatic respring and installs no privileged helper.

Installed files are under `/var/jb/usr/lib/TweakInject/`, `/var/jb/Library/PreferenceBundles/HiderPrefs.bundle/` and `/var/jb/Library/PreferenceLoader/Preferences/`. The installer creates only its own data directory, `/var/jb/var/mobile/Library/Hider`, owned by mobile (501:501). The app-ID array is `apps.plist` inside it. Selections survive upgrades and uninstall/reinstall; use **Disable all** to reset them. There is no `cfprefsd` preference-domain dependency.

### What Hider covers

The filesystem and symlink surfaces in [DETECTION.md](DETECTION.md) drive Hider's scope. Seeker continues to implement the document's 11 detection surfaces. Hider does not promise to conceal them all.

| File view | Intercepted APIs |
| --- | --- |
| POSIX lookup and metadata | `access`, `stat`, `lstat`, `faccessat`, `fstatat`, `statfs`, `statvfs`, `getattrlist`, `getattrlistat` |
| Opening and symlinks | `open`, `openat`, their exported `$NOCANCEL` variants, `fopen`, `opendir`, `readlink`, `readlinkat`, `realpath` |
| Directory listings | `readdir`, `readdir_r`; Foundation directory/subpath arrays and lazy enumerators |
| Foundation lookup | `NSFileManager` existence, access predicates, contents, item/filesystem attributes and symlink destination; `NSURL` reachability and resource values |

Hidden POSIX lookups return `ENOENT`; Foundation lookups return false/nil with a no-such-file error where supported. Ordinary paths call the original implementation. The shared policy covers `/var/jb` and descendants, its resolved bootstrap location, `/private/var` and `/private/etc` aliases, `/var/.jbroot-*`, and fixed package-manager, injection, SSH/Frida and preference paths in [PathPolicy.h](hider/PathPolicy.h). It does not hide all of `/var`, `/Library`, `/private/preboot` or the user's files. Relative and directory-relative paths are resolved against the current directory or directory descriptor. Existing aliases and missing children beneath aliases are checked too.

This is a userspace filter, not a filesystem permission boundary. Direct syscalls, raw `getdirentries`/`getattrlistbulk` buffers, alternate libc entry points, cached metadata, already-open descriptors and unhooked mutation APIs can still expose artifacts. Alias resolution can fail under sandbox restrictions or races; symlink-then-`..` paths are not fully virtualized. Root mount flags are unchanged. The fixed path list must be updated when bootstrap layouts change. Path checks may add filesystem work in selected apps.

Hider does not hide URL handlers, LaunchServices registration, dyld images, Objective-C classes, injected code, signature/debug flags, sandbox escapes, `fork`, ports, environment variables or IPC. Its dylib and enumerator class are themselves detectable. ElleKit can load Hider into UIKit processes even when unselected, but the constructor installs filesystem hooks only for explicitly selected `.app` bundles. App extensions and daemons are not covered. Hiding paths may also prevent selected apps or their other tweaks from loading legitimate jailbreak resources.

### Device validation still required

No device access was supplied; 0.1.1 has passed host checks only. On the reported phone, first confirm Settings loads and search finds known system/user apps, then select Seeker and restart it. Compare `/var/jb` metadata, readlink/realpath and `/var` listings before/after; non-filesystem detections may remain FIRED. Confirm a normal app-container file remains accessible. Uncheck Seeker and restart it to confirm its original view returns. Also test saved selections after reopening Settings, the protected rows, Disable all and package removal. A successful cross-build is not a passed device test.

### Hider research

Context7 was queried first for Theos and ElleKit; no AltList library was found. Its snippets covered hook APIs and rootless packaging but omitted the required Settings/private-API and ABI-conversion details. Those gaps were checked against [Theos's rootless guidance](https://theos.dev/docs/rootless), [allemande](https://github.com/p0358/allemande), [AltList's LaunchServices implementation](https://github.com/opa334/AltList/blob/main/LSApplicationProxy%2BAltList.m), and the project-local Theos PreferenceLoader template. AltList is reference material, not a dependency. [ElleKit's packaging source](https://github.com/dhinakg/ellekit-builder/blob/main/build.sh) documents the Substrate framework compatibility link and rootless TweakInject location. [Dopamine's preference hooks](https://github.com/opa334/Dopamine/blob/3.x/BaseBin/rootlesshooks/cfprefsd.x) explain its preference redirection; Hider uses its own rootless data file.

For the 0.1.0 crash investigation, Context7's Theos results again lacked current Linux compiler details. [LLVM's pointer-authentication documentation](https://clang.llvm.org/docs/PointerAuthentication.html) describes the signed class read-only-data pointer checked in 0.1.1. The compiler/linker combination was tested locally against the packaged binaries; this does not establish device compatibility by itself.
