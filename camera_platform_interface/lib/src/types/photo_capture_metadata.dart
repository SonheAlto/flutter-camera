// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Hauseful patch: metadata written into a photo at capture, so the app
// doesn't rewrite the file afterwards.

/// Metadata written into one photo when it is taken.
///
/// Used in [CameraPlatform.takePictureWithMetadata].
class PhotoCaptureMetadata {
  /// Creates a [PhotoCaptureMetadata].
  const PhotoCaptureMetadata({
    this.rotationDegrees = 0,
    this.latitude,
    this.longitude,
  }) : assert(
         rotationDegrees % 90 == 0,
         'rotationDegrees must be a multiple of 90',
       ),
       assert(
         (latitude == null) == (longitude == null),
         'latitude and longitude must be given together',
       );

  /// Degrees, clockwise and possibly negative, added to the EXIF orientation
  /// the camera writes.
  ///
  /// The EXIF orientations 1, 6, 3 and 8 stand for 0, 90, 180 and 270 degrees;
  /// any other value counts as 0. The sum is written back as one of those four.
  final int rotationDegrees;

  /// The latitude written into the photo's GPS metadata, in degrees.
  final double? latitude;

  /// The longitude written into the photo's GPS metadata, in degrees.
  final double? longitude;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PhotoCaptureMetadata &&
          rotationDegrees == other.rotationDegrees &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => Object.hash(rotationDegrees, latitude, longitude);

  @override
  String toString() =>
      'PhotoCaptureMetadata{rotationDegrees: $rotationDegrees, '
      'latitude: $latitude, longitude: $longitude}';
}
