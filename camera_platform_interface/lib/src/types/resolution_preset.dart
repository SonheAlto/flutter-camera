// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

/// Affect the quality of video recording and image capture:
///
/// A preset is treated as a target resolution, and exact values are not
/// guaranteed. Platform implementations may fall back to a higher or lower
/// resolution if a specific preset is not available.
enum ResolutionPreset {
  /// 352x288 on iOS, ~240p on Android and Web
  low,

  /// ~480p
  medium,

  /// ~720p
  high,

  /// ~1080p
  veryHigh,

  /// ~2160p
  ultraHigh,

  /// The highest resolution available.
  max,

  /// ~1280x960, 4:3, with the sensor's full field of view. Platforms pick the
  /// closest 4:3 size of at least 1280x960 (iOS often has 1440x1080 instead).
  ///
  /// Hauseful patch: not part of the official plugin. Only the Android
  /// (CameraX) and iOS implementations handle it.
  high4x3,
}
