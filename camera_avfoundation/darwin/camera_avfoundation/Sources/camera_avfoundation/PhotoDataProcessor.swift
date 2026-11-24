// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// Hauseful patch: photo capture options. A photo comes out of the camera
// already final (size, JPEG quality, orientation and GPS) and is written to
// disk once, so the app doesn't rewrite it after capture.

import AVFoundation
import Foundation
import ImageIO

/// How one photo is produced and what metadata is written into it.
struct PhotoCaptureOptions {
  /// The largest side, in pixels, the photo may have; nil keeps its size.
  let maxLongSide: Int?
  /// The JPEG quality, from 1 to 100; nil keeps the camera's default.
  let jpegQuality: Int?
  /// Degrees, clockwise and possibly negative, added to the photo's EXIF
  /// orientation.
  let rotationDegrees: Int
  /// The GPS position written into the photo, when both are given.
  let latitude: Double?
  let longitude: Double?
}

/// Turns a captured photo into its final file data, in memory.
enum PhotoDataProcessor {
  /// The photo's file data with `options` applied.
  ///
  /// A photo within the longest side keeps the camera's encoding and only has
  /// its metadata replaced. A larger one is scaled down from its in-memory
  /// bytes (a subsampled decode) and encoded once, with the metadata.
  static func fileData(for photo: AVCapturePhoto, options: PhotoCaptureOptions) -> Data? {
    let metadata = metadataApplying(options, to: photo.metadata)

    let dimensions = photo.resolvedSettings.photoDimensions
    let longSide = Int(max(dimensions.width, dimensions.height))
    if let maxLongSide = options.maxLongSide, longSide > maxLongSide,
      let originalData = photo.fileDataRepresentation(),
      let scaledData = scaledJPEGData(
        from: originalData, maxLongSide: maxLongSide, jpegQuality: options.jpegQuality,
        metadata: metadata)
    {
      return scaledData
    }

    return photo.fileDataRepresentation(with: MetadataReplacer(metadata: metadata))
  }

  /// `metadata` with the orientation turned by `options.rotationDegrees` and,
  /// when given, the GPS position (latitude, longitude and their references).
  static func metadataApplying(_ options: PhotoCaptureOptions, to metadata: [String: Any])
    -> [String: Any]
  {
    var result = metadata

    let currentOrientation =
      (metadata[kCGImagePropertyOrientation as String] as? NSNumber)?.intValue ?? 1
    let orientation = orientationWithRotation(
      currentOrientation, rotationDegrees: options.rotationDegrees)
    result[kCGImagePropertyOrientation as String] = orientation
    if var tiff = result[kCGImagePropertyTIFFDictionary as String] as? [String: Any] {
      tiff[kCGImagePropertyTIFFOrientation as String] = orientation
      result[kCGImagePropertyTIFFDictionary as String] = tiff
    }

    if let latitude = options.latitude, let longitude = options.longitude {
      var gps = result[kCGImagePropertyGPSDictionary as String] as? [String: Any] ?? [:]
      gps[kCGImagePropertyGPSLatitude as String] = abs(latitude)
      gps[kCGImagePropertyGPSLatitudeRef as String] = latitude >= 0 ? "N" : "S"
      gps[kCGImagePropertyGPSLongitude as String] = abs(longitude)
      gps[kCGImagePropertyGPSLongitudeRef as String] = longitude >= 0 ? "E" : "W"
      result[kCGImagePropertyGPSDictionary as String] = gps
    }

    return result
  }

  /// The EXIF orientation `exifOrientation` turned by `rotationDegrees`. Only
  /// the four rotations count: 1, 6, 3 and 8 stand for 0, 90, 180 and 270
  /// degrees, and any other value (a mirrored one) for 0.
  static func orientationWithRotation(_ exifOrientation: Int, rotationDegrees: Int) -> Int {
    let currentDegrees: Int
    switch exifOrientation {
    case 6: currentDegrees = 90
    case 3: currentDegrees = 180
    case 8: currentDegrees = 270
    default: currentDegrees = 0
    }
    switch ((currentDegrees + rotationDegrees) % 360 + 360) % 360 {
    case 90: return 6
    case 180: return 3
    case 270: return 8
    default: return 1
    }
  }

  /// `data` scaled down so its longest side is `maxLongSide`, as a JPEG with
  /// `metadata`. ImageIO decodes a JPEG subsampled when it only needs a
  /// smaller image, so the full-size image is never decoded. The pixels keep
  /// the sensor's orientation; the EXIF orientation still describes them.
  static func scaledJPEGData(
    from data: Data, maxLongSide: Int, jpegQuality: Int?, metadata: [String: Any]
  ) -> Data? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxLongSide,
      kCGImageSourceCreateThumbnailWithTransform: false,
      kCGImageSourceShouldCacheImmediately: true,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0, thumbnailOptions as CFDictionary)
    else { return nil }

    var properties = metadata
    properties.removeValue(forKey: kCGImagePropertyPixelWidth as String)
    properties.removeValue(forKey: kCGImagePropertyPixelHeight as String)
    if var exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] {
      exif[kCGImagePropertyExifPixelXDimension as String] = image.width
      exif[kCGImagePropertyExifPixelYDimension as String] = image.height
      properties[kCGImagePropertyExifDictionary as String] = exif
    }
    if let jpegQuality = jpegQuality {
      properties[kCGImageDestinationLossyCompressionQuality as String] =
        Double(jpegQuality) / 100.0
    }

    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output as CFMutableData, "public.jpeg" as CFString, 1, nil)
    else { return nil }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else { return nil }
    return output as Data
  }
}

/// Replaces a photo's metadata when its file data is created, without
/// re-encoding the image.
private final class MetadataReplacer: NSObject, AVCapturePhotoFileDataRepresentationCustomizer {
  private let metadata: [String: Any]

  init(metadata: [String: Any]) {
    self.metadata = metadata
  }

  func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
    metadata
  }
}
