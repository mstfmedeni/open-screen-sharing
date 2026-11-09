# Embedding (ClaudeDeck)

The `claudedeck` branch of this fork is upstream
[nekohasekai/open-screen-sharing](https://github.com/nekohasekai/open-screen-sharing) plus a few changes. It's built
into [ClaudeDeck](https://github.com/mstfmedeni/claudeDeck)'s iPhone/iPad app as the `ScreenSharingKit` framework,
from a git submodule at `Vendor/open-screen-sharing`.

## What this branch adds

| Change | Where | Upstream |
| --- | --- | --- |
| Mac keyboard and trackpad panel | `SessionUI/InputPanel.swift`, `MacKeyboard*.swift`, `TrackpadView.swift` | PR #21 |
| Keyboard on tapping a text field | `Session/SessionController.swift` | PR #16 |
| Mac keyboard on by default | `Model/AppSettings.swift` | fork only |
| Public API for a host app | `Embedding/` (`#if EMBEDDED`) | fork only |
| No `@main` when embedded; the session outlives its view | `OpenScreenSharingApp.swift`, `SessionUI/SessionView.swift` | fork only |

Fork-only code stays behind `#if EMBEDDED` or in `Embedding/`, so that merges from upstream rarely conflict with it.

## Taking an upstream fix

```sh
git checkout claudedeck
git fetch upstream            # upstream = https://github.com/nekohasekai/open-screen-sharing
git merge upstream/main       # merge, don't rebase: this branch is published
make lib                      # rebuild Libsharing.xcframework if the Go side changed
make build_ios                # check it still builds
git push fork claudedeck
```

Then, in ClaudeDeck:

```sh
git submodule update --remote Vendor/open-screen-sharing
python3 scripts/merge-screen-sharing-strings.py   # bring in new translations
git commit -am "Update open-screen-sharing"
```

Once an upstream PR listed above is merged, merging upstream brings in the same change; resolve any conflict
in favor of upstream.

## Building ScreenSharingKit

The framework target compiles everything under `OpenScreenSharing/` except `Demo/*.jpg`, the plists, the
entitlements and the resource catalogs. It needs these settings, which match this project:

- `SWIFT_VERSION = 6.0`
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- `SWIFT_APPROACHABLE_CONCURRENCY = YES`
- `SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY = YES`
- `SWIFT_ACTIVE_COMPILATION_CONDITIONS` includes `EMBEDDED`
- `IPHONEOS_DEPLOYMENT_TARGET = 15.0`: Perception's back-ported `Bindable` is unavailable at 17 and up
- Packages GRDB, Perception and Atomics, at the versions in this project's `Package.resolved`
- `Frameworks/Libsharing.xcframework`, built by `make lib`

## API

```swift
import ScreenSharingKit

ScreenSharingView()                                           // the tab; safe to remove and add back
ScreenSharingStore.shared.connect(host: "mac.local")          // keeps a live session to the same host
ScreenSharingStore.shared.open(URL(string: "vnc://mac.local")!)
ScreenSharingStore.shared.isConnected
ScreenSharingStore.shared.disconnect()
```

The session lives in `ScreenSharingStore`, not in the view. While no `ScreenSharingView` is on screen, the
computer stops sending pictures, but the connection stays open, the same as when the app is in the background.
