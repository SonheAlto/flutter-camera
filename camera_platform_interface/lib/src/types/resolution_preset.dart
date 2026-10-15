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

  // Hauseful patch: the 4:3 counterparts of high, veryHigh and ultraHigh, with
  // the sensor's full field of view. Not part of the official plugin; only the
  // Android (CameraX) and iOS implementations handle them. Platforms pick the
  // closest 4:3 size, and iOS skips binned formats, which look soft.

  /// ~1280x960, 4:3 (iOS: 1920x1440, its smallest 4:3 format that isn't binned).
  high4x3,

  /// ~1920x1440, 4:3.
  veryHigh4x3,

  /// ~3264x2448 (8 MP, the pixel count of 4K), 4:3.
  ultraHigh4x3,
}
