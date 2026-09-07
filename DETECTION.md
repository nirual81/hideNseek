# Local jailbreak detection on iOS

Jailbreak detection rarely depends on one file or one API. An app can inspect the filesystem, test sandbox behavior, list loaded code, query the Objective-C runtime, and look for installed jailbreak tools. Checks are often spread across the app, so hiding one obvious artifact may only remove one signal.

This document covers checks performed on the device.

## Detection surfaces

| Surface | What an app may inspect | Common jailbreak signal | Weight |
| --- | --- | --- | :---: |
| Filesystem | Paths, metadata, directory contents | `/var/jb`, bootstrap files, tweak preferences | Very high |
| Symlinks | Link type and destination | The rootless bootstrap link at `/var/jb` | Very high |
| App discovery | URL handlers and app registration | Sileo, Zebra, Filza, Dopamine | High |
| Loaded images | Mach-O images in the current process | ElleKit, systemhook, tweak or bypass dylibs | Very high |
| Objective-C runtime | Registered classes, methods, selectors | Objects introduced by tweaks or instrumentation | High |
| Sandbox behavior | Writes and access outside the app container | An operation succeeds where stock iOS rejects it | High |
| Process behavior | Restricted process APIs | `fork()` succeeds or fails differently from stock iOS | High |
| Debug state | Process flags and exception behavior | An attached debugger or altered tracing state | Medium |
| Instrumentation | Modules, classes, ports, executable pages | Frida Gadget, Frida server, hooks, or JIT-like memory | Very high |
| Code signing | Signature and entitlement state | Unexpected entitlements or modified process code | High |
| Environment and IPC | Variables, services, and reachable daemons | Injection variables or jailbreak services | Medium |

The weight column is a practical estimate, not a fixed score. Each app chooses its own checks and may combine weak signals.

## Filesystem checks

`/var/jb` is one of the clearest signs of a rootless jailbreak. Looking it up by name is only the simplest test. The same artifact can be observed through:

- Foundation file APIs
- POSIX calls such as `open`, `access`, `stat`, and `lstat`
- directory enumeration
- metadata and filesystem queries
- symlink inspection and path resolution

These views need to agree. If a direct lookup says that `/var/jb` is absent while `/var` enumeration still returns it, the mismatch is itself useful evidence. The same applies when `stat` and `lstat` disagree in a way that stock iOS would not produce.

Detectors also look beyond `/var/jb`. Known bootstrap directories, package-manager files, tweak preferences, launch daemons, and other jailbreak-specific paths can reveal the environment even when the main link is hidden.

## Jailbreak app discovery

Bundle identifiers are only one route to installed apps. A detector may also query URL handlers such as:

- `sileo://`
- `zbra://`
- `filza://`
- `dopamine://`

Application registration, bundle discovery, icon databases, and files left by jailbreak apps provide other views of the same state. Blocking one lookup does not make those views consistent.

## Loaded code and runtime state

Injection leaves evidence inside the target process. A detector can enumerate loaded Mach-O images and search their paths or names for components such as ElleKit, `systemhook.dylib`, tweak dylibs, jailbreak-bypass libraries, and instrumentation frameworks.

This is a hard limit for an injected hiding layer: the code that changes the app's view must first enter the app. Its own image, classes, methods, hooks, or executable memory may then become detectable.

The Objective-C runtime is a separate inspection surface. An app can list registered classes, inspect method implementations, or query known class and selector names. Renaming a dylib does not remove runtime objects introduced by that dylib.

## Behavioral checks

Some checks ask whether the device behaves like stock iOS instead of looking for a named jailbreak artifact. Common examples are:

- trying to write outside the app sandbox
- opening restricted paths
- calling `fork()` or related process APIs
- comparing filesystem permissions and metadata with expected values

A clean-looking path list is not enough if an operation that should fail succeeds. These tests are useful because they survive changes to jailbreak names and directory layouts.

## Debugging and instrumentation

Apps often group anti-debugging and anti-instrumentation checks with jailbreak detection. They may inspect debugger flags, tracing behavior, loaded modules, listening services, Objective-C classes, or unusual executable memory.

Frida is a common target, but the category is broader than Frida. An app may reject any process state that suggests runtime inspection or method replacement, even if it finds no Dopamine-specific artifact.

## A useful model

Treat local detection as a consistency problem. Several interfaces observe the same underlying state:

```text
                 filesystem APIs
                symlink metadata
App process --> application discovery --> observed device state
                loaded images
                runtime and behavior
```

An isolated false result is easy to contradict. A convincing stock view requires matching results across all interfaces the app can reach. New checks usually exploit a view that an earlier approach forgot to cover.

## Scope by difficulty

Artifact checks are the simplest group: paths, symlinks, URL schemes, jailbreak apps, preferences, and bootstrap files. Runtime and behavioral checks are harder because they inspect the process performing the concealment and compare its behavior with stock iOS. Filesystem consistency sits between the two; there are many APIs, but they still describe one filesystem.

No local concealment layer should claim universal coverage. Detection code changes, apps combine signals differently, and injection can expose the mechanism used to hide other evidence.

## References

- [IOSSecuritySuite jailbreak checks](https://github.com/securing/IOSSecuritySuite/blob/master/IOSSecuritySuite/JailbreakChecker.swift)
- [OWASP MASTG: Jailbreak detection](https://mas.owasp.org/MASTG-KNOW-0084/)
