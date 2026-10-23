# flutter-camera (Hauseful patches)

Patched copies of three packages from the official Flutter `camera` plugin, used by the fhost app through `dependency_overrides`.

| Package | Upstream version |
|---|---|
| `camera_platform_interface` | 2.13.0 |
| `camera_android_camerax` | 0.7.2 |
| `camera_avfoundation` | 0.10.3+1 |

The app-facing `camera` package is not patched; it picks these up through the overrides. Only Android and iOS are supported. `camera_web` and the desktop implementations are not patched, so they don't compile against the new presets; fhost doesn't target them.

## What the patch adds

The full, per-file list of changes is in [PATCHES.md](PATCHES.md). A summary:

**4:3 counterparts of `high`, `veryHigh` and `ultraHigh`:** `ResolutionPreset.high4x3` (~1280×960), `veryHigh4x3` (~1920×1440) and `ultraHigh4x3` (~3264×2448). They keep the sensor's full field of view and are captured straight from the camera hardware, with no reprocessing, for photos and video.

- **Android (Dart only):**
  - Photos: CameraX is asked for the preset's size with a 4:3 aspect ratio strategy.
  - Video: the 16:9 counterpart's quality (HD, FHD, UHD), with the `Recorder` set to 4:3.
- **iOS:** the smallest 4:3 device format of at least the preset's size that isn't binned (binned formats look soft). Without one, it falls back to the 16:9 counterpart. Photos and video come out at that format's size.

**Android preview stabilization:** on phones that support Camera2's `PREVIEW_STABILIZATION` (Android 13+), it is offered as `VideoStabilizationMode.level2`. The official plugin only maps Camera2's "on" (`level1`).

Every change is marked with a `Hauseful patch` comment.

## Branches

- **`upstream`:** the exact pub.dev releases listed above, untouched. Never commit our changes here.
- **`main`:** `upstream` plus our patch.

## Updating to a newer upstream release

1. `git switch upstream`.
2. Replace a package directory with the new release from the pub cache (`~/.pub-cache/hosted/pub.dev/<package>-<version>`; run `flutter pub cache add <package> --version <version>` first if it's missing). Update the table above, and commit as "Import <package> <version>".
3. `git switch main && git merge upstream`. Git re-applies our patch; resolve conflicts where upstream changed the same lines.
4. In fhost, update the `ref:` in `dependency_overrides` (or run `flutter pub get` for a local path), then rebuild and test both platforms.
