# What this fork changes

Everything in this repository is the official Flutter `camera` plugin code, unchanged, except for the changes listed here. This is the full list: 25 files across 3 packages (including generated Pigeon code and tests), 978 added lines, 24 replaced.

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
5. **Android honors the video bitrate** passed in `MediaSettings.videoBitrate`.
6. **Photo capture options:** a photo can come out of the camera already final, with a largest side, a JPEG quality, an orientation and a GPS position, written to disk once.

Nothing else is changed: focus, zoom, flash and every other behavior are the official code, and `takePicture` itself still works as before.

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

For the changes below, one file changed, `lib/src/android_camera_camerax.dart`, in Dart only. The photo capture options (section 4) also touch Java, the Pigeon files and Gradle.

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

**Video bitrate** (the `Recorder` setup)
- Official 0.7.2: `MediaSettings.videoBitrate` is never passed on, so CameraX uses the bitrate of the phone's own recording profile for the chosen quality.
- Patched: it is passed to the `Recorder` as `targetVideoEncodingBitRate`, the same one-line change the official plugin made in 0.7.5. Without a bitrate, nothing changes. `audioBitrate` is still ignored on Android.

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
- **Frame rate:** when a frame rate is set, the official startup code locks the camera device before applying the preset, then sets the frame duration. `setCaptureSessionPreset` takes a `deviceIsLocked` flag, and the 4:3 branch skips its own lock/unlock when the caller already holds the lock. Locking twice could release the device early, before the frame duration is set. The format search for the frame rate only considers formats of the same size, so it never swaps in a binned one.

**Generated files** (`Messages.swift`, `lib/src/messages.g.dart`, `pigeons/messages.dart`, plus the mapping in `lib/src/avfoundation_camera.dart`)
- `PlatformResolutionPreset` gets the three new values (`high4x3 = 6`, `veryHigh4x3 = 7`, `ultraHigh4x3 = 8`), and `_pigeonResolutionPreset` maps the Dart presets to them.
- `Messages.swift` and `messages.g.dart` are generated from `pigeons/messages.dart`. All three were edited by hand to match, so running Pigeon again produces the same code.

## 4. Photo capture options (all three packages)

An app that takes hundreds of photos in a row shouldn't have to read each one back, rewrite its metadata and re-encode it. These options make the camera write the photo once, already final.

**API** (`camera_platform_interface`):
- `PhotoOutputSettings(maxLongSide, jpegQuality)` and `CameraPlatform.setPhotoOutputSettings`: how photos are produced. They apply to cameras created after the call (Android picks the photo size when the camera is set up) and to every later capture.
- `PhotoCaptureMetadata(rotationDegrees, latitude, longitude)` and `CameraPlatform.takePictureWithMetadata(cameraId, metadata)`: takes a photo with that metadata written into it.
- Orientation rule: `rotationDegrees` (clockwise, possibly negative) is added to the EXIF orientation the camera wrote. The orientations 1, 6, 3 and 8 stand for 0, 90, 180 and 270 degrees; any other value (a mirrored one) counts as 0. GPS gets latitude, longitude and their N/S, E/W references.
- The `camera` package doesn't expose these; an app calls them through `CameraPlatform.instance` with the controller's `cameraId`.

**Android** (`camera_android_camerax`):
- `ImageCapture` gets its own resolution selector: the preset's one when the preset fits `maxLongSide`, otherwise the preset's aspect ratio with the size scaled down to `maxLongSide` and the closest lower size the camera has. The camera pipeline produces the photo at that size, with no CPU work; preview and video keep the preset. CameraX picks among the sizes the phone lists, so the photo can come out somewhat smaller than `maxLongSide` (e.g. 1280 wide for a 1400 limit).
- `jpegQuality` goes to `ImageCapture.Builder.setJpegQuality`.
- `takePictureWithMetadata` passes the location through CameraX's `ImageCapture.Metadata`, so CameraX writes it in the same save (it also writes the capture time as the GPS time). The orientation is then updated in the EXIF alone (`androidx.exifinterface`, no pixel re-encode), and only when it changes.
- Files: `pigeons/camerax_library.dart` (an `ImageCapture` constructor parameter and one method), the generated `camerax_library.g.dart` (Pigeon 26.1.7, the version upstream used, then `dart format`) and `CameraXLibrary.g.kt` (the generator's new code added by hand in the existing ktfmt style), `ImageCaptureProxyApi.java`, `android_camera_camerax.dart`, `build.gradle.kts`, and the tests that build an `ImageCapture`.

**iOS** (`camera_avfoundation`):
- `takePictureWithOptions` (Pigeon) carries the settings and metadata as plain values, so the message codec is unchanged. `Messages.swift`, `messages.g.dart` and `pigeons/messages.dart` were edited by hand, as for the presets: the pinned Pigeon (27.3.2) doesn't resolve with the Flutter SDK in use.
- `DefaultCamera.captureToFile(options:)` uses the options' JPEG quality for the capture and hands the options to `SavePhotoDelegate`. A photo taken with options is always JPEG.
- `PhotoDataProcessor.swift` (new) runs on the delegate's IO queue, before the file is written:
  - a photo within `maxLongSide` keeps the camera's encoding; only its metadata is replaced (`fileDataRepresentation(with:)`), with no re-encode;
  - a larger one (e.g. the 3840×2160 ultra-wide) is scaled from its in-memory bytes with `CGImageSourceCreateThumbnailAtIndex` (ImageIO decodes the JPEG subsampled) and encoded once at the JPEG quality, with the metadata. The pixels keep the sensor's orientation; the EXIF orientation still describes them.
- `Camera.swift` and the test `MockCamera.swift` gain the `captureToFile(options:)` overload.

## What is not changed

- **`camera`**, the package the app imports, is untouched. It picks up these three through `dependency_overrides`.
- **`camera_web` and the desktop packages** aren't updated for the new values. `camera_web` has `switch` statements over `ResolutionPreset` without a `default`, so it doesn't compile against the new enum. That's accepted because fhost only builds for Android and iOS.
- **No resizing or re-encoding outside the photo capture options:** `takePicture` and video are untouched. With the options, only iOS photos larger than `maxLongSide` are scaled and re-encoded, in memory, before they are written (an earlier version shrank every iOS photo; it was removed because most iOS format sizes are close enough to the targets).

## Updating to a new official release

See the "Updating to a newer upstream release" section of [README.md](README.md). In short: import the new release on `upstream`, merge `upstream` into `main`, and re-check the files above for conflicts. The `Hauseful patch` comments are where Git will conflict if the official code changed there.
