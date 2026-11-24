// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package io.flutter.plugins.camerax;

import android.location.Location;
import android.util.Log;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.camera.core.ImageCapture;
import androidx.camera.core.ImageCaptureException;
import androidx.camera.core.resolutionselector.ResolutionSelector;
import androidx.exifinterface.media.ExifInterface;
import java.io.File;
import java.io.IOException;
import java.util.concurrent.Executors;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * ProxyApi implementation for {@link ImageCapture}. This class may handle instantiating native
 * object instances that are attached to a Dart instance or handle method calls on the associated
 * native class or an instance of that class.
 */
class ImageCaptureProxyApi extends PigeonApiImageCapture {
  static final String TEMPORARY_FILE_NAME = "CAP";
  static final String JPG_FILE_TYPE = ".jpg";

  ImageCaptureProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  @NonNull
  @Override
  public ImageCapture pigeon_defaultConstructor(
      @Nullable ResolutionSelector resolutionSelector,
      @Nullable Long targetRotation,
      @Nullable CameraXFlashMode flashMode,
      @Nullable Long jpegQuality) {
    final ImageCapture.Builder builder = new ImageCapture.Builder();
    // Hauseful patch: the JPEG quality of captured photos.
    if (jpegQuality != null) {
      builder.setJpegQuality(jpegQuality.intValue());
    }
    if (targetRotation != null) {
      builder.setTargetRotation(targetRotation.intValue());
    }
    if (flashMode != null) {
      // This sets the requested flash mode, but may fail silently.
      switch (flashMode) {
        case AUTO:
          builder.setFlashMode(ImageCapture.FLASH_MODE_AUTO);
          break;
        case OFF:
          builder.setFlashMode(ImageCapture.FLASH_MODE_OFF);
          break;
        case ON:
          builder.setFlashMode(ImageCapture.FLASH_MODE_ON);
          break;
      }
    }
    if (resolutionSelector != null) {
      builder.setResolutionSelector(resolutionSelector);
    }
    return builder.build();
  }

  @Override
  public void setFlashMode(
      @NonNull ImageCapture pigeonInstance, @NonNull CameraXFlashMode flashMode) {
    int nativeFlashMode = -1;
    switch (flashMode) {
      case AUTO:
        nativeFlashMode = ImageCapture.FLASH_MODE_AUTO;
        break;
      case OFF:
        nativeFlashMode = ImageCapture.FLASH_MODE_OFF;
        break;
      case ON:
        nativeFlashMode = ImageCapture.FLASH_MODE_ON;
    }
    pigeonInstance.setFlashMode(nativeFlashMode);
  }

  @Override
  public void takePicture(
      @NonNull ImageCapture pigeonInstance,
      @NonNull SystemServicesManager systemServicesManager,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    final File outputDir = getPigeonRegistrar().getContext().getCacheDir();
    File temporaryCaptureFile;
    try {
      temporaryCaptureFile = File.createTempFile(TEMPORARY_FILE_NAME, JPG_FILE_TYPE, outputDir);
    } catch (IOException | SecurityException e) {
      ResultCompat.failure(e, callback);
      return;
    }

    final ImageCapture.OutputFileOptions outputFileOptions =
        createImageCaptureOutputFileOptions(temporaryCaptureFile);
    final ImageCapture.OnImageSavedCallback onImageSavedCallback =
        createOnImageSavedCallback(temporaryCaptureFile, systemServicesManager, callback);

    pigeonInstance.takePicture(
        outputFileOptions, Executors.newSingleThreadExecutor(), onImageSavedCallback);
  }

  // Hauseful patch: a capture with its metadata written into the photo, so the
  // app doesn't rewrite the file afterwards. CameraX writes the location in the
  // same save; the orientation is updated in the EXIF alone, without
  // re-encoding the image, and only when it changes.
  @Override
  public void takePictureWithMetadata(
      @NonNull ImageCapture pigeonInstance,
      @NonNull SystemServicesManager systemServicesManager,
      @Nullable Double latitude,
      @Nullable Double longitude,
      long rotationDegrees,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    final File outputDir = getPigeonRegistrar().getContext().getCacheDir();
    File temporaryCaptureFile;
    try {
      temporaryCaptureFile = File.createTempFile(TEMPORARY_FILE_NAME, JPG_FILE_TYPE, outputDir);
    } catch (IOException | SecurityException e) {
      ResultCompat.failure(e, callback);
      return;
    }

    final ImageCapture.Metadata metadata = new ImageCapture.Metadata();
    if (latitude != null && longitude != null) {
      final Location location = new Location("");
      location.setLatitude(latitude);
      location.setLongitude(longitude);
      location.setTime(System.currentTimeMillis());
      metadata.setLocation(location);
    }
    final ImageCapture.OutputFileOptions outputFileOptions =
        new ImageCapture.OutputFileOptions.Builder(temporaryCaptureFile)
            .setMetadata(metadata)
            .build();

    final File file = temporaryCaptureFile;
    final ImageCapture.OnImageSavedCallback onImageSavedCallback =
        new ImageCapture.OnImageSavedCallback() {
          @Override
          public void onImageSaved(@NonNull ImageCapture.OutputFileResults outputFileResults) {
            addRotationToExifOrientation(file, rotationDegrees);
            ResultCompat.success(file.getAbsolutePath(), callback);
          }

          @Override
          public void onError(@NonNull ImageCaptureException exception) {
            systemServicesManager.onCameraError(
                getImageCaptureExceptionDescription(exception.getImageCaptureError()));
            ResultCompat.failure(exception, callback);
          }
        };

    pigeonInstance.takePicture(
        outputFileOptions, Executors.newSingleThreadExecutor(), onImageSavedCallback);
  }

  /**
   * Hauseful patch: adds {@code rotationDegrees} (clockwise, possibly negative) to the photo's EXIF
   * orientation, rewriting the file only when the orientation changes. A failure is logged and the
   * photo is kept as CameraX wrote it.
   */
  static void addRotationToExifOrientation(@NonNull File file, long rotationDegrees) {
    try {
      final ExifInterface exif = new ExifInterface(file.getAbsolutePath());
      final int current =
          exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL);
      final int updated = orientationWithRotation(current, rotationDegrees);
      if (updated == current) return;
      exif.setAttribute(ExifInterface.TAG_ORIENTATION, String.valueOf(updated));
      exif.saveAttributes();
    } catch (IOException | RuntimeException e) {
      Log.w("ImageCaptureProxyApi", "Failed to update the photo's EXIF orientation", e);
    }
  }

  /**
   * Hauseful patch: the EXIF orientation {@code exifOrientation} turned by {@code rotationDegrees}.
   * Only the four rotations count: 1, 6, 3 and 8 stand for 0, 90, 180 and 270 degrees, and any
   * other value (a mirrored one) for 0.
   */
  static int orientationWithRotation(int exifOrientation, long rotationDegrees) {
    final int currentDegrees;
    switch (exifOrientation) {
      case ExifInterface.ORIENTATION_ROTATE_90:
        currentDegrees = 90;
        break;
      case ExifInterface.ORIENTATION_ROTATE_180:
        currentDegrees = 180;
        break;
      case ExifInterface.ORIENTATION_ROTATE_270:
        currentDegrees = 270;
        break;
      default:
        currentDegrees = 0;
    }
    final long combined = ((currentDegrees + rotationDegrees) % 360 + 360) % 360;
    if (combined == 90) return ExifInterface.ORIENTATION_ROTATE_90;
    if (combined == 180) return ExifInterface.ORIENTATION_ROTATE_180;
    if (combined == 270) return ExifInterface.ORIENTATION_ROTATE_270;
    return ExifInterface.ORIENTATION_NORMAL;
  }

  @Override
  public void setTargetRotation(ImageCapture pigeonInstance, long rotation) {
    pigeonInstance.setTargetRotation((int) rotation);
  }

  @Nullable
  @Override
  public ResolutionSelector resolutionSelector(@NonNull ImageCapture pigeonInstance) {
    return pigeonInstance.getResolutionSelector();
  }

  ImageCapture.OutputFileOptions createImageCaptureOutputFileOptions(@NonNull File file) {
    return new ImageCapture.OutputFileOptions.Builder(file).build();
  }

  @NonNull
  ImageCapture.OnImageSavedCallback createOnImageSavedCallback(
      @NonNull File file,
      @NonNull SystemServicesManager systemServicesManager,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    return new ImageCapture.OnImageSavedCallback() {
      @Override
      public void onImageSaved(@NonNull ImageCapture.OutputFileResults outputFileResults) {
        ResultCompat.success(file.getAbsolutePath(), callback);
      }

      @Override
      public void onError(@NonNull ImageCaptureException exception) {
        systemServicesManager.onCameraError(
            getImageCaptureExceptionDescription(exception.getImageCaptureError()));
        ResultCompat.failure(exception, callback);
      }
    };
  }

  /**
   * Returns an error description for each {@link ImageCaptureException} error code.
   *
   * <p>See
   * https://developer.android.com/reference/androidx/camera/core/ImageCaptureException#getImageCaptureError()
   * for details on each error type.
   */
  String getImageCaptureExceptionDescription(int imageCaptureErrorCode) {
    switch (imageCaptureErrorCode) {
      case ImageCapture.ERROR_FILE_IO:
        return "An error occurred while attempting to save the captured image to a file.";
      case ImageCapture.ERROR_CAPTURE_FAILED:
        return "The camera framework failed to fulfill the image capture request.";
      case ImageCapture.ERROR_CAMERA_CLOSED:
        return "Image capture failed due to the camera being closed.";
      case ImageCapture.ERROR_INVALID_CAMERA:
        return "The ImageCapture use case was bound to an invalid camera by the Flutter camera"
            + " plugin. If you see this error, please file an issue if you cannot find one"
            + " that already exists: https://github.com/flutter/flutter/issues/.";
      default:
        return "An unknown error has occurred while attempting to take a picture. Check the logs"
            + " for more details.";
    }
  }
}
