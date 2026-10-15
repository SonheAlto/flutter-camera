// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import AVFoundation
import Flutter
import Foundation
import ImageIO

/// The completion handler block for save photo operations.
/// Can be called from either main queue or IO queue.
/// If success, `path` will be present and `error` will be nil. Otherwise, `path` will be nil and
/// `error` will be present.
/// path - the path for successfully saved photo file.
/// error - photo capture error or IO error.
typealias SavePhotoDelegateCompletionHandler = (String?, Error?) -> Void

/// Delegate object that handles photo capture results.
class SavePhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
  /// The file path for the captured photo.
  private let path: String

  /// The queue on which captured photos are written to disk.
  private let ioQueue: DispatchQueue

  /// The completion handler block for capture and save photo operations.
  let completionHandler: SavePhotoDelegateCompletionHandler

  /// Hauseful patch: when set, a larger JPEG photo is shrunk so its longer side is this many
  /// pixels before it is written.
  private let maxPixelSize: Int?

  /// Hauseful patch: the JPEG quality, from 0 to 1, a shrunk photo is encoded with.
  private let jpegQuality: CGFloat

  /// The path for captured photo file.
  /// Exposed for unit tests to verify the captured photo file path.
  var filePath: String {
    path
  }

  /// Initialize a photo capture delegate.
  /// path - the path for captured photo file.
  /// ioQueue - the queue on which captured photos are written to disk.
  /// completionHandler - The completion handler block for save photo operations. Can
  /// be called from either main queue or IO queue.
  init(
    path: String,
    ioQueue: DispatchQueue,
    maxPixelSize: Int? = nil,
    jpegQuality: CGFloat = 1,
    completionHandler: @escaping SavePhotoDelegateCompletionHandler
  ) {
    self.path = path
    self.ioQueue = ioQueue
    self.maxPixelSize = maxPixelSize
    self.jpegQuality = jpegQuality
    self.completionHandler = completionHandler
    super.init()
  }

  /// Handler to write captured photo data into a file.
  /// - Parameters:
  ///   - error: The capture error
  ///   - photoDataProvider: A closure that provides photo data
  func handlePhotoCaptureResult(
    error: Error?,
    photoDataProvider: @escaping () -> WritableData?
  ) {
    if let error = error {
      completionHandler(nil, error)
      return
    }

    ioQueue.async { [weak self] in
      guard let strongSelf = self else { return }

      do {
        var data = photoDataProvider()
        if let maxPixelSize = strongSelf.maxPixelSize, let photo = data as? Data,
          let shrunk = SavePhotoDelegate.shrinkJPEG(
            photo, maxPixelSize: maxPixelSize, quality: strongSelf.jpegQuality)
        {
          data = shrunk
        }
        try data?.writeToPath(strongSelf.path, options: .atomic)
        strongSelf.completionHandler(strongSelf.path, nil)
      } catch {
        strongSelf.completionHandler(nil, error)
      }
    }
  }

  /// Hauseful patch: re-encodes `jpeg` so its longer side is `maxPixelSize`, keeping its
  /// metadata (orientation included, since the pixels are not rotated). Returns nil when the
  /// photo is already that small or can't be processed, so the original is written instead.
  static func shrinkJPEG(_ jpeg: Data, maxPixelSize: Int, quality: CGFloat) -> Data? {
    guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int,
      max(width, height) > maxPixelSize
    else {
      return nil
    }
    let thumbnailOptions: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: false,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source, 0, thumbnailOptions as CFDictionary)
    else {
      return nil
    }
    let output = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        output, "public.jpeg" as CFString, 1, nil)
    else {
      return nil
    }
    var outputProperties = properties
    outputProperties[kCGImageDestinationLossyCompressionQuality] = quality
    outputProperties[kCGImagePropertyPixelWidth] = image.width
    outputProperties[kCGImagePropertyPixelHeight] = image.height
    if var exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] {
      exif[kCGImagePropertyExifPixelXDimension] = image.width
      exif[kCGImagePropertyExifPixelYDimension] = image.height
      outputProperties[kCGImagePropertyExifDictionary] = exif
    }
    CGImageDestinationAddImage(destination, image, outputProperties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return output as Data
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    handlePhotoCaptureResult(error: error) {
      photo.fileDataRepresentation()
    }
  }
}
