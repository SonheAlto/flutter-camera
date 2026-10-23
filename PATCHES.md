# What this fork changes

Everything in this repository is the official Flutter `camera` plugin code, unchanged, except for the changes listed here. This is the full list: 8 code files across 3 packages, 178 added lines, 4 replaced.

| Package | Upstream version |
|---|---|
| `camera_platform_interface` | 2.13.0 |
| `camera_android_camerax` | 0.7.2 |
| `camera_avfoundation` | 0.10.3+1 |

Every change in the code is marked with a `Hauseful patch` comment, so this works to find them:

```bash
grep -rn "Hauseful patch" --include='*.dart' --include='*.swift' .
```

To see the exact diff against the official code, compare the two branches. `upstream` holds the untouched pub.dev releases; `main` has our changes on top.

```bash
git diff upstream main -- camera_platform_interface camera_android_camerax camera_avfoundation
```

## In short

1. **Three new 4:3 resolution presets:** `high4x3`, `veryHigh4x3` and `ultraHigh4x3`. The official plugin has no 4:3 option below `max`.
2. **4:3 video on Android**, for those presets.
3. **iOS picks a full-detail 4:3 camera format** for them, skipping the soft "binned" ones.
4. **Android preview stabilization** (Android 13+) offered as a second stabilization level.

Nothing else is changed: capture, focus, zoom, flash and every other behavior are the official code.

## 1. The new presets: `camera_platform_interface`

The official `ResolutionPreset` has `low`, `medium`, `high` (16:9), `veryHigh` (16:9), `ultraHigh` (16:9) and `max`. We add three values:

| New value | 16:9 counterpart | Target size |
|---|---|---|
| `high4x3` | `high` | ~1280×960 |
| `veryHigh4x3` | `veryHigh` | ~1920×1440 |
| `ultraHigh4x3` | `ultraHigh` | ~3264×2448 (8 MP, the pixel count of 4K) |

| File | Change |
|---|---|
| `lib/src/types/resolution_preset.dart` | The three enum values, with doc comments. |
| `lib/src/method_channel/method_channel_camera.dart` | `_serializeResolutionPreset` returns `'high4x3'`, `'veryHigh4x3'` and `'ultraHigh4x3'` for them. Without this, the switch wouldn't compile. |

These sizes are targets. Each platform picks the closest size the device has, and nothing is resized after capture.

## 2. Android: `camera_android_camerax`

One file changed, `lib/src/android_camera_camerax.dart`, in Dart only. There's no Kotlin or Java change.

**Photos: the preset's size, at a 4:3 aspect ratio** (`_getResolutionSelectorFromPreset`)
- Official: `high` asks CameraX for 1280×720 with a 16:9 aspect ratio strategy.
- Patched: each 4:3 preset asks for its size (1280×960, 1920×1440 or 3264×2448) with `AspectRatio.ratio4To3`, using the same mechanism the official `high` and `low` presets use. CameraX returns the closest 4:3 size the phone lists.
- This selector also drives preview and image analysis, so the preview is 4:3 too.

**Video: 4:3 recording** (`_getQualitySelectorFromPreset` and the `Recorder` setup)
- Official: video quality comes from the preset (`high` → HD, `veryHigh` → FHD, `ultraHigh` → UHD), and the recorder uses CameraX's default 16:9.
- Patched: each 4:3 preset uses its 16:9 counterpart's quality (so HD, FHD and UHD), and the `Recorder` is created with the 4:3 aspect ratio (`_isFourByThreePreset` decides). The video comes out as CameraX's 4:3 size for that quality, e.g. 960×720 for HD.

**Stabilization: Android 13+ preview stabilization as `level2`** (`_getSupportedVideoStabilizationModeMap`)
- Official: of Camera2's stabilization modes, only "on" (value 1) is exposed, as `level1`.
- Patched: Camera2's `PREVIEW_STABILIZATION` (value 2) is also exposed, as `level2`, on phones that list it. It steadies the preview as well as the recording, more strongly than "on".
- Only modes the phone itself lists are exposed, so phones without it are unaffected.

## 3. iOS: `camera_avfoundation`

**Choosing the camera format** (`DefaultCamera.swift`)

On iOS, the official presets set an `AVCaptureSession` preset, such as `.hd1280x720`, which are all 16:9. Our presets pick a camera format directly instead:

- **`setCaptureSessionPreset`:** for a 4:3 preset, it picks a format with `smallestFourByThreeFormat`, uses `sessionPreset = .inputPriority` (the same way the official `max` does) and sets the format as the camera's active one. Photos and video then come out at that format's own size.
- **`fourByThreeTarget(for:)`:** the smallest size each preset accepts, and which 16:9 preset to fall back to.

  | Preset | Smallest size accepted | Falls back to |
  |---|---|---|
  | `high4x3` | 1280×960 | `high` |
  | `veryHigh4x3` | 1920×1440 | `veryHigh` |
  | `ultraHigh4x3` | 3264×2448 | `ultraHigh` |

- **`smallestFourByThreeFormat`:** from the camera's formats it keeps those that are exactly 4:3, at least the minimum size, and **not binned** (binned formats merge sensor pixels and look soft, e.g. 1440×1080 on the iPhone 17 main camera). From those it picks the one with the fewest pixels, preferring the same pixel format subtype as the current one. It skips the compressed `btp2` format the Flutter engine can't use, as the official code does.
- **Fallback:** if no format qualifies, the camera uses the 16:9 counterpart instead, so it keeps working.

**Generated files** (`Messages.swift`, `lib/src/messages.g.dart`, `pigeons/messages.dart`, plus the mapping in `lib/src/avfoundation_camera.dart`)
- `PlatformResolutionPreset` gets the three new values (`high4x3 = 6`, `veryHigh4x3 = 7`, `ultraHigh4x3 = 8`), and `_pigeonResolutionPreset` maps the Dart presets to them.
- `Messages.swift` and `messages.g.dart` are generated from `pigeons/messages.dart`. All three were edited by hand to match, so running Pigeon again produces the same code.

## What is not changed

- **`camera`**, the package the app imports, is untouched. It picks up these three through `dependency_overrides`.
- **`camera_web` and the desktop packages** aren't updated for the new values. `camera_web` has `switch` statements over `ResolutionPreset` without a `default`, so it doesn't compile against the new enum. That's accepted because fhost only builds for Android and iOS.
- **No capture-time resizing or re-encoding:** nothing in the patch touches the image after the camera produces it. An earlier version shrank iOS photos in memory; it was removed because iOS format sizes are close enough to the targets.

## Updating to a new official release

See the "Updating to a newer upstream release" section of [README.md](README.md). In short: import the new release on `upstream`, merge `upstream` into `main`, and re-check the files above for conflicts. The `Hauseful patch` comments are where Git will conflict if the official code changed there.
