import 'dart:io';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;

class AppwriteService {
  // Appwrite SDK clients
  late final Client _client;
  late final Storage _storage;
  
  // Constants
  static const String _endpoint = 'https://cloud.appwrite.io/v1';
  static const String projectId = '683932070023292fdf26';
  static const String _bucketId = '684d55f9000259403eb0';
  
  // Private constructor
  AppwriteService._() {
    _client = Client()
      ..setEndpoint(_endpoint)
      ..setProject(projectId)
      ..setSelfSigned(status: true);
    
    _storage = Storage(_client);
  }
  
  // Singleton instance
  static final AppwriteService _instance = AppwriteService._();
  
  // Factory constructor to return the singleton instance
  factory AppwriteService() => _instance;
  
  // File upload method
  Future<Map<String, dynamic>?> uploadFile({
    required BuildContext context,
    List<String>? allowedExtensions,
  }) async {
    try {
      // Pick file
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowedExtensions ?? ['jpg', 'jpeg', 'png', 'mp4', 'pdf'],
      );
      
      if (result == null || result.files.isEmpty) {
        return null; // User cancelled the picker
      }
      
      PlatformFile file = result.files.first;
      String fileName = file.name;
      String? mimeType = lookupMimeType(fileName);
      
      // Generate a unique ID for the file
      final String fileId = ID.unique();
      
      // Upload the file based on platform
      if (kIsWeb) {
        // Web platform
        final uploadedFile = await _storage.createFile(
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
        );
        
        return {
          'fileId': uploadedFile.$id,
          'fileName': fileName,
          'mimeType': mimeType,
          'size': file.size,
        };
      } else {
        // Mobile platform
        final uploadedFile = await _storage.createFile(
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
        );
        
        return {
          'fileId': uploadedFile.$id,
          'fileName': fileName,
          'mimeType': mimeType,
          'size': file.size,
        };
      }
    } catch (e) {
      print('Error uploading file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error uploading file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
  }
  
  // Helper method to get headers for file requests
  Map<String, String> getFileHeaders() {
    if (!kIsWeb) return {};
    
    return {
      'X-Appwrite-Project': projectId,
      'X-Appwrite-Response-Format': '1.4.0',
      'X-Appwrite-Web-Session': 'true',
    };
  }
  
  // Get file preview URL (for thumbnails)
  String getFilePreviewUrl(String fileId, {int width = 400, int height = 400}) {
    if (!kIsWeb) {
      final baseUrl = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/preview';
      return '$baseUrl?width=$width&height=$height';
    }
    
    // For web, include session token in URL
    final baseUrl = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/preview';
    final params = 'width=$width&height=$height&project=$projectId';
    final url = '$baseUrl?$params';
    print('Generated preview URL: $url'); // Debug log
    return url;
  }
  
  // Get file view URL with proper headers for web
  String getFileViewUrl(String fileId) {
    if (!kIsWeb) {
      return '$_endpoint/storage/buckets/$_bucketId/files/$fileId/view';
    }
    
    // For web, include session token in URL
    final url = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/view?project=$projectId';
    print('Generated view URL: $url'); // Debug log
    return url;
  }
  
  // Get file download URL
  String getFileDownloadUrl(String fileId) {
    if (!kIsWeb) {
      return '$_endpoint/storage/buckets/$_bucketId/files/$fileId/download';
    }
    
    // For web, include session token in URL
    final url = '$_endpoint/storage/buckets/$_bucketId/files/$fileId/download?project=$projectId';
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
} 