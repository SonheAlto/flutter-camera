// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Hauseful patch: how photos come out of the camera, so the app doesn't have
// to shrink or re-encode them after capture.

/// How still photos are produced.
///
/// Used in [CameraPlatform.setPhotoOutputSettings].
class PhotoOutputSettings {
  /// Creates a [PhotoOutputSettings].
  const PhotoOutputSettings({this.maxLongSide, this.jpegQuality})
    : assert(
        maxLongSide == null || maxLongSide > 0,
        'maxLongSide must be null or greater than zero',
      ),
      assert(
        jpegQuality == null || (jpegQuality >= 1 && jpegQuality <= 100),
        'jpegQuality must be null or between 1 and 100',
      );

  /// The largest side, in pixels, a photo may have.
  ///
  /// A photo whose longer side is larger comes out scaled down to it, keeping
  /// its aspect ratio. Android picks the photo size at the source, so the
  /// photo may come out somewhat smaller than this; iOS scales the captured
  /// photo before it is written. Null keeps the size the preset gives.
  final int? maxLongSide;

  /// The JPEG quality photos are encoded at, from 1 (lowest) to 100 (highest).
  ///
  /// Null keeps the platform's default.
  final int? jpegQuality;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoOutputSettings &&
          maxLongSide == other.maxLongSide &&
          jpegQuality == other.jpegQuality;

  @override
  int get hashCode => Object.hash(maxLongSide, jpegQuality);

  @override
  String toString() =>
      'PhotoOutputSettings{maxLongSide: $maxLongSide, jpegQuality: $jpegQuality}';
}
