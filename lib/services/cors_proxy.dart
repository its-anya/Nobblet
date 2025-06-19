import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class CorsProxy {
  static final Dio _dio = Dio();
  
  // Convert image URL to data URL for web
  static Future<String> getProxiedImageUrl(String originalUrl, Map<String, String> headers) async {
    if (!kIsWeb) {
      return originalUrl; // Return original URL for non-web platforms
    }
    
    try {
      // Attempt to fetch the image as bytes
      final response = await _dio.get<Uint8List>(
        originalUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
          validateStatus: (status) => status! < 500,
        ),
      );
      
      if (response.statusCode == 200 && response.data != null) {
        // Convert image bytes to base64
        final base64Image = base64Encode(response.data!);
        
        // Determine MIME type from URL or use a default
        String mimeType = 'image/jpeg';
        if (originalUrl.toLowerCase().endsWith('.png')) {
          mimeType = 'image/png';
        } else if (originalUrl.toLowerCase().endsWith('.gif')) {
          mimeType = 'image/gif';
        } else if (originalUrl.toLowerCase().endsWith('.webp')) {
          mimeType = 'image/webp';
        }
        
        // Create data URL
        return 'data:$mimeType;base64,$base64Image';
      }
    } catch (e) {
      print('Error creating proxied image URL: $e');
    }
    
    // Return original URL if conversion fails
    return originalUrl;
  }
} 