# flutter-camera (Hauseful patches)

Patched copies of three packages from the official Flutter `camera` plugin, used by the fhost app through `dependency_overrides`.

| Package | Upstream version |
|---|---|
| `camera_platform_interface` | 2.13.0 |
| `camera_android_camerax` | 0.7.2 |
| `camera_avfoundation` | 0.10.3+1 |

The app-facing `camera` package is not patched; it picks these up through the overrides. Only Android and iOS are supported. `camera_web` and the desktop implementations are not patched, so they don't compile against `ResolutionPreset.high4x3`; fhost doesn't target them.

## What the patch adds

- **`ResolutionPreset.high4x3`:** 4:3 photos captured at about 1280×960, straight from the camera hardware, with no reprocessing.
  - **Android:** CameraX picks its 1280×960 JPEG output (4:3 aspect ratio strategy), or the closest 4:3 size the phone lists.
  - **iOS:** the smallest 4:3 device format of at least 1280×960 is selected. Photos come out at that format's size: 1280×960 if the device has it, otherwise the next one up, typically 1440×1080.

## Branches

- **`upstream`:** the exact pub.dev releases listed above, untouched. Never commit our changes here.
- **`main`:** `upstream` plus our patch.

## Updating to a newer upstream release

1. `git switch upstream`.
2. Replace a package directory with the new release from the pub cache (`~/.pub-cache/hosted/pub.dev/<package>-<version>`; run `flutter pub cache add <package> --version <version>` first if it's missing). Update the table above, and commit as "Import <package> <version>".
3. `git switch main && git merge upstream`. Git re-applies our patch; resolve conflicts where upstream changed the same lines.
4. In fhost, update the `ref:` in `dependency_overrides` (or run `flutter pub get` for a local path), then rebuild and test both platforms.
