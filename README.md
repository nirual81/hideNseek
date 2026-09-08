# hideNseek

**Seeker** reports local jailbreak detections and builds as either a sideloadable IPA or a rootless `.deb`. **Hider** selectively hides known filesystem paths inside apps you choose and remains a jailbreak tweak. Both target iOS 18.0.1. Source lives in `seeker/` and `hider/`; development tools stay in this project's `dev/` directory.

For the hiding tweak, see [Hider](#hider). The Seeker build and usage follow below.

To install Seeker without Sileo, see [Build and sideload Seeker's IPA](#build-and-sideload-seekers-ipa).

Seeker shows which local jailbreak detections fire, with the evidence from each check. It is a small Objective-C/UIKit app for **iOS 18.0.1 or later**, packaged as a rootless `.deb` for Dopamine 3 and Sileo.

Open the app to run a scan. **Fired** shows findings; **All checks** also shows checks with no observed signal and checks that were unavailable. Tap refresh or pull down to rerun. Results stay in memory. The app has no backend or telemetry.

## Build on Linux

The setup script supports x86_64 Linux and installs tools inside `dev/`. It downloads pinned versions of Theos, the Linux iOS toolchain and the patched iOS SDK, and checks the archive hashes. It does not change shell profiles or install system packages.

On this project's original Arch/Omarchy host, all host prerequisites were already installed. On a new machine, install missing prerequisites using your package manager:

```sh
# Arch / Omarchy, only if needed:
sudo pacman -S --needed base-devel git curl perl rsync fakeroot xz zip python libbsd openssl ncurses

# Debian / Ubuntu alternative:
sudo apt install build-essential git curl perl rsync fakeroot xz-utils zip python3 libbsd0 libtinfo6 libuuid1 zlib1g
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

## Build and sideload Seeker's IPA

The IPA contains the same Seeker app and 37 checks. It has no Hider injection code, Debian installer scripts or jailbreak-only entitlements. It can be signed and installed without an active jailbreak. Hider itself cannot be installed as a standalone IPA and still requires Dopamine/ElleKit.

After the shared setup above, run from the project root:

```sh
make -C seeker package PACKAGE_FORMAT=ipa
python3 dev/check.py --ipa
```

Output: `seeker/packages/com.hidenseek.seeker_0.1.0.ipa`. The argument is `PACKAGE_FORMAT=ipa`, not `THEOS_PACKAGE_FORMAT=ipa`. Theos's existing IPA packager uses the host `zip` command; no additional packaging tool is needed. IPA objects and staging live under `seeker/.theos/ipa`, separate from the default rootless build. To clean just this build, use `make -C seeker clean PACKAGE_FORMAT=ipa`. Omitting `PACKAGE_FORMAT=ipa` still builds the Sileo `.deb`.

This is input for a **sideload signer**, not an already provisioned installation. The binary has only a local ad hoc signature, with no Apple certificate, provisioning profile or account entitlements. Your signing tool must sign the app and supply a matching profile for your device. Apple's [ad hoc provisioning instructions](https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile/) describe the certificate, App ID and registered-device requirements; that distribution workflow is different from the local ad hoc signature used by the Linux build. No account, certificate or device was configured here.

To install and test:

1. Uncheck Seeker in Hider. The IPA uses `com.hidenseek.seeker`, the same bundle ID as the `.deb`. Remove only the **Seeker** package in Sileo before sideloading to avoid that conflict. Keep Hider installed. Alternatively, if your signer supports changing the bundle ID, use a distinct ID for side-by-side installation.
2. Import the `.ipa` into your IPA signing/sideload tool. Complete its signing and installation flow using your own account or certificate/profile. Follow any device trust or Developer Mode prompts. Opening this unprovisioned archive in Files alone does not install it.
3. Launch the sideloaded Seeker with Hider disabled for it first. Confirm it scans normally. On a non-jailbroken launch, restricted/private checks may report UNAVAILABLE; that is expected behavior, not an installation error.
4. With Dopamine active, open Settings → Hider, pull to refresh and select the sideloaded Seeker's **actual bundle ID**. A signer may change the ID, so the old selection may not match. Allow tweak injection for that app, fully close it, then launch it again. No respring is needed just for the selection change.

A normal sideload puts Seeker in an app installation container outside `/var/jb/Applications`. This removes the known conflict where Hider's path policy hides the Sileo copy's own app bundle. It is a diagnostic comparison, not a confirmed fix for the selected-app crash. If the sideloaded copy also crashes, uncheck it and retrieve its newest startup trace from its data container as described below. Keep PayPal unchecked during this test.

The IPA check validates archive CRCs and the exact `Payload/Seeker.app` contents, executable permissions, arm64, iOS 18.0.1 minimum, signature presence, empty entitlements and system-only dependencies. It rejects rootless load paths and extra payload files. It cannot validate your later signing/provisioning or run the app on iOS.

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

The current package, **0.1.2, is a diagnostic build** for a selected-app startup crash. It is not a confirmed crash fix. Use Seeker for this test and leave PayPal unchecked; see [Collect the startup trace](#collect-the-startup-trace).

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

Output: `hider/packages/com.hidenseek.hider_0.1.2_iphoneos-arm64.deb`.

Both the tweak and Settings bundle contain arm64 and arm64e slices, targeting iOS 18.0.1. Clang 22 emits native arm64e metadata. The build retains the project-local Theos SDK 16.5, ld64 linker and signing tools; it no longer uses allemande conversion or needs a system-wide `oldabi` package. The Makefile explicitly selects the cross-linker and new-ABI static libraries. DWARF 4 debug information keeps the bundled debug-symbol tool compatible. A clean build should produce no legacy-ABI or debug-attribute warnings.

The check compiles and runs the shared path policy against boundaries, dot components, aliases and real symlinks. It tests diagnostic-file creation, private permissions, descriptor flags, checkpoint contents and errno preservation. It also inspects both package slices, iOS minimums, Settings registration, dependencies, the versioned arm64e ABI header, authenticated Objective-C class read-only-data/isa/superclass and CFString pointers, and signed code-page hashes. These checks cannot run the hooks on Linux.

When upgrading the build tools from 0.1.0, run `make -C hider clean` before the build command to discard old objects. Install the `.deb`, not intermediate binaries from `.theos/obj`.

### Settings crash reported in 0.1.0

The reported device is an iPhone 11 Pro Max on iOS 18.0.1, Dopamine 3.0.9, ElleKit 1.2 and PreferenceLoader 2.2.8. Version 0.1.0 closed Settings before any transition. Inspection found a legacy arm64e ABI header and unauthenticated class read-only-data pointers left by partial conversion. The earlier check missed those fields. Version 0.1.1 replaced that build path; the strengthened check rejects 0.1.0 and passes later builds. The user confirmed that **0.1.1 fixed the Settings page**. No crash stack was supplied, so the precise runtime failure remains unconfirmed.

### Collect the startup trace

With 0.1.1, the user reports that selected PayPal and Seeker apps crash immediately. Seeker launches normally after unchecking it. The installed version was confirmed in Sileo. No usable iOS crash report was found. Version 0.1.2 adds checkpoints without changing the hiding policy or hook order.

The supplied 0.1.2 trace records all 20 C and 19 Objective-C installation returns. Its `access("/", F_OK)` succeeds, while `access("/var/jb", F_OK)` returns `-1` with `errno=2` (ENOENT). It stops at `constructor/returning`, before the main-queue checkpoint. That marker precedes dispatch scheduling and autorelease-pool cleanup; it does not prove the constructor returned or identify a faulting instruction. The next comparison is the [sideloaded Seeker IPA](#build-and-sideload-seekers-ipa), outside the hidden bootstrap tree. Hider remains at 0.1.2; no further diagnostic revision or crash fix has been applied.

A second trace, explicitly collected from PayPal, has the same checkpoints and results. Hiding Seeker's own rootless app bundle cannot explain the PayPal failure on its own. The IPA comparison remains useful, but does not establish that changing Seeker's installation location fixes the shared startup problem.

Install 0.1.2 using the instructions below. Leave PayPal unchecked. Select Seeker in Hider, force-close Seeker from the app switcher, then launch it once. After the crash, uncheck Seeker to restore normal launching.

Using a file browser or SSH with access to Seeker's **data container**, open `Library/Caches` and copy the newest file whose name starts with `Hider-startup-`. This is not Seeker's `.app` installation directory. For a normally containerized launch, the full path is `/var/mobile/Containers/Data/Application/<Seeker-data-UUID>/Library/Caches/Hider-startup-<random>`. The cache path is obtained from Foundation at runtime; the UUID is device-specific. Send the file's contents, or report that no file was created.

Each selected launch creates a new file exclusively, with mode 0600. It contains the diagnostic version, loaded architecture, C symbol/Objective-C selector checkpoints and results from read-only `access` checks on `/` and `/var/jb`. It does not collect account data, app content or ongoing filesystem activity, and nothing is uploaded. Writes use a descriptor opened before hooking, so hiding the pathname later does not prevent checkpoint writes. The descriptor closes when the main-queue checkpoint runs or the process exits. File creation and writes are best-effort; a missing file does not prove hooks were disabled.

A final `c/before` or `objc/before` line identifies an installation call with no recorded completion. `probe/before` without its matching `probe/after` narrows the investigation to that filesystem call or concurrent activity. `main-queue/reached` only confirms startup got that far, not that the app is healthy. Do not infer an exact faulting instruction from a checkpoint alone. Trace files remain in the cache until removed by the user, app or OS; this diagnostic build creates one per selected launch. Remove the tracing code after isolating the failure.

### Install and recover

Use a supported device already running Dopamine 3 on iOS 18.0.1. Install its compatible rootless **ElleKit** (`ellekit`) and **PreferenceLoader** (`preferenceloader`) through Sileo. ElleKit provides injection and the Substrate-compatible hook API; PreferenceLoader loads the Settings page. Hider does not install or configure the jailbreak itself.

Transfer the `.deb` and install through Sileo where local-package opening is supported. Alternatively, using the same device-specific SSH settings as the Seeker instructions:

```sh
scp hider/packages/com.hidenseek.hider_0.1.2_iphoneos-arm64.deb mobile@IPHONE_IP:/var/mobile/
ssh mobile@IPHONE_IP
# On the device:
sudo /var/jb/usr/bin/dpkg -i /var/mobile/com.hidenseek.hider_0.1.2_iphoneos-arm64.deb
```

Install 0.1.2 over the existing version; saved selections remain intact. If dependencies are missing, install them in Sileo and rerun the device command. Complete any restart requested by Sileo, then **force-close Settings from the app switcher and reopen it** so it cannot reuse the old loaded bundle. Force-close affected apps too, since an upgrade does not unload their old dylib. For this diagnostic build, follow the Seeker-only trace procedure above. If the page is missing, check PreferenceLoader and that injection is enabled for Settings. If hiding does not apply, check that Dopamine/Choicy or another injection manager allows Hider in that app. Disabling injection also disables Hider. Changing the selection itself needs an app relaunch, not a respring.

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

No device access was supplied to the agent. The user confirmed Settings works in 0.1.1, but selected apps crash. The supplied 0.1.2 trace confirms its access probe hides `/var/jb`; full startup remains unverified. Test the sideloaded Seeker first. After startup is fixed, compare Seeker's `/var/jb` metadata, readlink/realpath and `/var` listings before/after; non-filesystem detections may remain FIRED. Confirm a normal app-container file remains accessible. Uncheck Seeker and restart it to confirm its original view returns. Also test search, saved selections after reopening Settings, the protected rows, Disable all and package removal. A successful cross-build is not a passed device test.

### Hider research

Context7 was queried first for Theos and ElleKit; no AltList library was found. Its snippets covered hook APIs and rootless packaging but omitted the required Settings/private-API and ABI-conversion details. Those gaps were checked against [Theos's rootless guidance](https://theos.dev/docs/rootless), [allemande](https://github.com/p0358/allemande), [AltList's LaunchServices implementation](https://github.com/opa334/AltList/blob/main/LSApplicationProxy%2BAltList.m), and the project-local Theos PreferenceLoader template. AltList is reference material, not a dependency. [ElleKit's packaging source](https://github.com/dhinakg/ellekit-builder/blob/main/build.sh) documents the Substrate framework compatibility link and rootless TweakInject location. [Dopamine's preference hooks](https://github.com/opa334/Dopamine/blob/3.x/BaseBin/rootlesshooks/cfprefsd.x) explain its preference redirection; Hider uses its own rootless data file.

For the 0.1.0 crash investigation, Context7's Theos results again lacked current Linux compiler details. [LLVM's pointer-authentication documentation](https://clang.llvm.org/docs/PointerAuthentication.html) describes the signed class read-only-data pointer checked in 0.1.1. The compiler/linker combination was tested locally against the packaged binaries; this does not establish device compatibility by itself.

For the selected-app crash, Context7's ElleKit snippets described the hook API but did not establish 1.2/iOS 18 behavior. Upstream [Substrate wrappers](https://github.com/tealbathingsuit/ellekit/blob/main/ellekit/API/MobileSubstrate.swift), [C hooking](https://github.com/tealbathingsuit/ellekit/blob/main/ellekit/Languages/C/Hook.swift) and [Objective-C hooking](https://github.com/tealbathingsuit/ellekit/blob/main/ellekit/Languages/Objective-C.swift) were inspected for the gaps. Those are main-branch references, not a verified match to the user's installed ElleKit 1.2 binary; no dependency upgrade or hook-engine change is prescribed from them.
