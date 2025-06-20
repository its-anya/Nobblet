import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:dio/dio.dart';
import 'dart:typed_data';
import '../theme/app_theme.dart';
import 'cors_proxy.dart';
import 'dart:async';

class AppwriteService {
  // Appwrite SDK clients
  late final Client _client;
  late final Storage _storage;
  late final Dio _dio;
  
  // Constants
  static const String _endpoint = 'https://nyc.cloud.appwrite.io/v1';
  static const String projectId = '68552b2f00049e3242a1';
  static const String _bucketId = '68552b870010295697eb';
  
  // Custom upload progress steps
  static const List<int> _progressSteps = [0, 2, 5, 10, 13, 15, 18, 20, 23, 30, 38, 46, 56, 61, 68, 72, 74, 79, 80, 86, 89, 90, 92, 94, 96, 98, 99, 100];
  
  // Private constructor
  AppwriteService._() {
    _client = Client()
      ..setEndpoint(_endpoint)
      ..setProject(projectId)
      ..setSelfSigned(status: true);
    
    // Web platform specific settings
    // Note: setMode was removed as it's not available in the current SDK version
    
    _storage = Storage(_client);
    
    // Initialize Dio for better CORS handling
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: getFileHeaders(),
    ));
  }
  
  // Singleton instance
  static final AppwriteService _instance = AppwriteService._();
  
  // Factory constructor to return the singleton instance
  factory AppwriteService() => _instance;
  
  // File upload method
  Future<Map<String, dynamic>?> uploadFile({
    required BuildContext context,
    List<String>? allowedExtensions,
    Function(double progress, String timeRemaining, bool isComplete)? onProgressUpdate,
  }) async {
    try {
      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions ?? ['jpg', 'jpeg', 'png', 'mp4', 'pdf', 'zip', 'rar', 'tar', '7z', 'gz'],
      );
      
      if (result == null || result.files.isEmpty) {
        return null; // User cancelled the picker
      }
      
      PlatformFile file = result.files.first;
      String fileName = file.name;
      String? mimeType = lookupMimeType(fileName);
      String fileSize = _formatFileSize(file.size);
      
      // Generate a unique ID for the file
      final String fileId = ID.unique();
      
      // Immediately return file info to display in chat while uploading
      final fileInfo = {
        'fileId': fileId,
        'fileName': fileName,
        'mimeType': mimeType,
        'size': file.size,
        'formattedSize': fileSize,
        'isUploading': true,
        'uploadProgress': 0.0,
      };
      
      // Initial progress update with 0%
      if (onProgressUpdate != null) {
        onProgressUpdate(0.0, "Starting upload...", false);
      }
      
      // Upload progress tracking
      DateTime startTime = DateTime.now();
      int currentStepIndex = 0;
      
      // Create a completer to handle the upload process
      final completer = Completer<Map<String, dynamic>>();
      
      // Timer for custom progress updates
      Timer? customProgressTimer;
      
      // Setup custom progress timer
      customProgressTimer = Timer.periodic(Duration(milliseconds: 200 + (file.size ~/ 50000)), (timer) {
        if (currentStepIndex < _progressSteps.length - 1) {
          currentStepIndex++;
          double progressValue = _progressSteps[currentStepIndex] / 100.0;
          
          String estimatedTimeRemaining = "Uploading...";
          if (currentStepIndex < _progressSteps.length - 3) {
            final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;
            final remainingSteps = _progressSteps.length - currentStepIndex - 1;
            final remainingSeconds = (elapsedSeconds / currentStepIndex) * remainingSteps;
            
            if (remainingSeconds > 60) {
              final minutes = (remainingSeconds / 60).floor();
              final seconds = remainingSeconds % 60;
              estimatedTimeRemaining = '$minutes min ${seconds.toStringAsFixed(0)} sec';
            } else {
              estimatedTimeRemaining = '${remainingSeconds.toStringAsFixed(0)} sec';
            }
          } else if (currentStepIndex >= _progressSteps.length - 3) {
            estimatedTimeRemaining = "Finishing...";
          }
          
          if (onProgressUpdate != null) {
            onProgressUpdate(progressValue, estimatedTimeRemaining, false);
          }
          
          print("Custom progress update: ${_progressSteps[currentStepIndex]}%");
          
          // If we reach the last step, stop the timer
          if (currentStepIndex == _progressSteps.length - 2) { // 99%
            timer.cancel();
          }
        }
      });
      
      // Upload the file based on platform without showing dialog
      if (kIsWeb) {
        // Web platform
        _storage.createFile(
          bucketId: _bucketId,
          fileId: fileId,
          file: InputFile.fromBytes(
            bytes: file.bytes!,
            filename: fileName,
            contentType: mimeType,
          ),
          permissions: [
            Permission.read(Role.any()),
            Permission.write(Role.any()),
          ],
          onProgress: (progress) {
            // We're ignoring the real progress and using our custom progress instead
            print("Web upload actual progress: ${progress.progress * 100}%");
          },
        ).then((uploadedFile) {
          // Cancel custom progress timer if it's still running
          customProgressTimer?.cancel();
          
          // Update with completed state (100%)
          if (onProgressUpdate != null) {
            onProgressUpdate(1.0, "Complete", true);
          }
          completer.complete(fileInfo);
        }).catchError((error) {
          // Cancel custom progress timer if it's still running
          customProgressTimer?.cancel();
          
          print('Error uploading file: $error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: AppTheme.errorColor),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Error uploading file: ${error.toString()}')),
                ],
              ),
              backgroundColor: AppTheme.secondaryBackgroundColor,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          completer.completeError(error);
        });
        
      } else {
        // Mobile platform
        _storage.createFile(
          bucketId: _bucketId,
          fileId: fileId,
          file: InputFile.fromPath(
            path: file.path!,
            filename: fileName,
            contentType: mimeType,
          ),
          permissions: [
            Permission.read(Role.any()),
            Permission.write(Role.any()),
          ],
          onProgress: (progress) {
            // We're ignoring the real progress and using our custom progress instead
            print("Mobile upload actual progress: ${progress.progress * 100}%");
          },
        ).then((uploadedFile) {
          // Cancel custom progress timer if it's still running
          customProgressTimer?.cancel();
          
          // Update with completed state (100%)
          if (onProgressUpdate != null) {
            onProgressUpdate(1.0, "Complete", true);
          }
          completer.complete(fileInfo);
        }).catchError((error) {
          // Cancel custom progress timer if it's still running
          customProgressTimer?.cancel();
          
          print('Error uploading file: $error');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: AppTheme.errorColor),
                  const SizedBox(width: 12),
                  Expanded(child: Text('Error uploading file: ${error.toString()}')),
                ],
              ),
              backgroundColor: AppTheme.secondaryBackgroundColor,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          completer.completeError(error);
        });
      }
      
      // Wait for upload to complete and return final file info
      try {
        await completer.future;
        return fileInfo;
      } catch (e) {
        // Error already handled in catchError above
        return null;
      }
    } catch (e) {
      print('Error selecting file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: AppTheme.errorColor),
              const SizedBox(width: 12),
              Expanded(child: Text('Error uploading file: ${e.toString()}')),
            ],
          ),
          backgroundColor: AppTheme.secondaryBackgroundColor,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
      return null;
    }
  }
  
  // Helper method to update progress (kept for compatibility but not used for custom steps)
  void _updateProgress(
    double progress, 
    DateTime startTime, 
    Function(double progress, String timeRemaining, bool isComplete)? onProgressUpdate,
    [double lastReportedProgress = 0.0, 
    DateTime? lastUpdateTime]
  ) {
    if (onProgressUpdate == null) return;
    
    // Handle invalid progress values
    if (progress.isNaN || progress.isInfinite || progress < 0) {
      progress = 0.0;
    }
    
    // Ensure progress is between 0 and 1
    progress = progress.clamp(0.0, 1.0);
    
    // Throttle updates for smoother visual progress
    // Don't update too frequently, and don't jump too much
    final now = DateTime.now();
    final lastTime = lastUpdateTime ?? startTime;
    final timeSinceLastUpdate = now.difference(lastTime).inMilliseconds;
    
    // If progress jumped too quickly, throttle it
    if (progress > lastReportedProgress + 0.2 && progress < 0.95 && timeSinceLastUpdate < 500) {
      // Gradual increase instead of jumping
      progress = lastReportedProgress + 0.05;
    }
    
    // For final completion, don't throttle to ensure we reach 100%
    if (progress >= 0.95) {
      progress = 0.99; // Hold at 99% until explicitly marked complete
    }
    
    String estimatedTimeRemaining = "Calculating...";
    
    // Calculate estimated time remaining
    if (progress > 0.01) {  // Only start showing time after 1% progress
      final elapsedSeconds = DateTime.now().difference(startTime).inSeconds;
      if (elapsedSeconds > 0) {
        final estimatedTotalSeconds = elapsedSeconds / progress;
        final remainingSeconds = (estimatedTotalSeconds - elapsedSeconds).round();
        
        if (remainingSeconds > 60) {
          final minutes = (remainingSeconds / 60).floor();
          final seconds = remainingSeconds % 60;
          estimatedTimeRemaining = '$minutes min ${seconds.toString().padLeft(2, '0')} sec';
        } else {
          estimatedTimeRemaining = '$remainingSeconds sec';
        }
        
        // When almost complete, show "Finishing..." message
        if (progress > 0.95) {
          estimatedTimeRemaining = "Finishing...";
        }
      }
    }
    
    print('Progress update: ${(progress * 100).toStringAsFixed(1)}%, Time remaining: $estimatedTimeRemaining');
    onProgressUpdate(progress, estimatedTimeRemaining, false);
  }
  
  // Helper method to format file size
  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }
  
  // Helper method to get icon for file type
  IconData getIconForFileType(String fileName) {
    if (isImageFile(fileName)) {
      return Icons.image;
    } else if (isVideoFile(fileName)) {
      return Icons.video_file;
    } else if (isPdfFile(fileName)) {
      return Icons.picture_as_pdf;
    } else if (isZipFile(fileName)) {
      return Icons.archive;
    } else {
      return Icons.insert_drive_file;
    }
  }
  
  // Helper method to get headers for file requests
  Map<String, String> getFileHeaders() {
    // Include headers for both web and mobile platforms
    Map<String, String> headers = {
      'X-Appwrite-Project': projectId,
      'X-Appwrite-Response-Format': '1.4.0',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
      'Pragma': 'no-cache',
      'Expires': '0',
    };
    
    // Add web-specific headers
    if (kIsWeb) {
      headers['X-Appwrite-Web-Session'] = 'true';
    }
    
    return headers;
  }
  
  // Get file preview URL (for thumbnails)
  String getFilePreviewUrl(String fileId, {int width = 400, int height = 400}) {
    // Add timestamp for cache busting
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Use download URL instead of preview to avoid CORS issues
    if (kIsWeb) {
      return '$_endpoint/storage/buckets/$_bucketId/files/$fileId/download?project=$projectId&t=$timestamp';
    }
    
    if (!kIsWeb) {
      final baseUrl = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/preview';
      return '$baseUrl?width=$width&height=$height&t=$timestamp';
    }
    
    // For web, include session token in URL
    final baseUrl = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/preview';
    final params = 'width=$width&height=$height&project=$projectId&t=$timestamp';
    final url = '$baseUrl?$params';
    print('Generated preview URL: $url'); // Debug log
    return url;
  }
  
  // Get file view URL with proper headers for web
  String getFileViewUrl(String fileId) {
    // Add timestamp for cache busting
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // Use download URL instead of view to avoid CORS issues
    if (kIsWeb) {
      return '$_endpoint/storage/buckets/$_bucketId/files/$fileId/download?project=$projectId&t=$timestamp';
    }
    
    if (!kIsWeb) {
      return '$_endpoint/storage/buckets/$_bucketId/files/$fileId/view?t=$timestamp';
    }
    
    // For web, include session token in URL
    final url = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/view?project=$projectId&t=$timestamp';
    print('Generated view URL: $url'); // Debug log
    return url;
  }
  
  // Get file download URL
  String getFileDownloadUrl(String fileId) {
    // Add timestamp for cache busting
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    
    // For both web and mobile, include project ID and timestamp
    final url = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/download?project=$projectId&t=$timestamp';
    print('Generated download URL: $url'); // Debug log
    return url;
  }
  
  // Delete file
  Future<void> deleteFile(String fileId) async {
    try {
      await _storage.deleteFile(
        bucketId: _bucketId,
        fileId: fileId,
      );
    } catch (e) {
      print('Error deleting file: $e');
      rethrow;
    }
  }
  
  // Get file extension from file name
  String getFileExtension(String fileName) {
    return p.extension(fileName).toLowerCase().replaceAll('.', '');
  }
  
  // Check if file is an image
  bool isImageFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext);
  }
  
  // Check if file is a video
  bool isVideoFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['mp4', 'mov', 'avi', 'webm'].contains(ext);
  }
  
  // Check if file is a PDF
  bool isPdfFile(String fileName) {
    return getFileExtension(fileName) == 'pdf';
  }
  
  // Check if file is a ZIP file
  bool isZipFile(String fileName) {
    final ext = getFileExtension(fileName);
    return ['zip', 'rar', 'tar', '7z', 'gz'].contains(ext);
  }
  
  // Fetch image using Dio (better CORS handling)
  Future<Uint8List?> fetchImageWithDio(String fileId) async {
    try {
      final url = getFileViewUrl(fileId);
      final response = await _dio.get<Uint8List>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          headers: getFileHeaders(),
          validateStatus: (status) => status! < 500,
        ),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        return response.data;
      } else {
        print('Dio fetch failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error fetching image with Dio: $e');
      return null;
    }
  }
  
  // Get image as memory network image source
  Future<ImageProvider> getImageProvider(String fileId) async {
    try {
      if (kIsWeb) {
        // Try direct file view URL first
        final directUrl = getFileViewUrl(fileId);
        
        // Convert to data URL using our CORS proxy
        final proxiedUrl = await CorsProxy.getProxiedImageUrl(directUrl, getFileHeaders());
        
        if (proxiedUrl.startsWith('data:')) {
          // If successfully converted to data URL, use it
          return NetworkImage(proxiedUrl);
        }
        
        // If data URL conversion failed, try fetching bytes directly
        final imageBytes = await fetchImageWithDio(fileId);
        if (imageBytes != null) {
          return MemoryImage(imageBytes);
        }
      }
      
      // For non-web platforms, or as fallback, use regular network image
      return NetworkImage(
        getFileViewUrl(fileId),
        headers: getFileHeaders(),
      );
    } catch (e) {
      print('Error in getImageProvider: $e');
      // Ultimate fallback - try preview URL instead of view URL
      return NetworkImage(
        getFilePreviewUrl(fileId),
        headers: getFileHeaders(),
      );
    }
  }
} 