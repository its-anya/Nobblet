import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class CorsProxy {
  static final Dio _dio = Dio();
  
  // Cache for URLs to avoid repeated network requests
  static final Map<String, String> _urlCache = {};
  
  // Convert image URL to data URL for web
  static Future<String> getProxiedImageUrl(String originalUrl, Map<String, String> headers) async {
    if (!kIsWeb) {
      return originalUrl; // Return original URL for non-web platforms
    }
    
    // Check if URL is already in cache
    final cacheKey = '$originalUrl-${headers.hashCode}';
    if (_urlCache.containsKey(cacheKey)) {
      print('Using cached URL for: $originalUrl');
      return _urlCache[cacheKey]!;
    }
    
    try {
      // Add cache-busting parameter
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urlWithTimestamp = originalUrl.contains('?') 
          ? '$originalUrl&t=$timestamp' 
          : '$originalUrl?t=$timestamp';
      
      print('Fetching image from: $urlWithTimestamp');
      
      // Attempt to fetch the image as bytes
      final response = await _dio.get<Uint8List>(
        urlWithTimestamp,
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
        final dataUrl = 'data:$mimeType;base64,$base64Image';
        
        // Cache the URL for future use
        _urlCache[cacheKey] = dataUrl;
        
        return dataUrl;
      }
    } catch (e) {
      print('Error creating proxied image URL: $e');
    }
    
    // Return original URL if conversion fails
    return originalUrl;
  }
  
  // Get a video URL that works with web platform
  static String getProxiedVideoUrl(String originalUrl) {
    if (!kIsWeb) {
      return originalUrl; // Return original URL for non-web platforms
    }
    
    // Check if URL is already in cache
    if (_urlCache.containsKey(originalUrl)) {
      print('Using cached video URL for: $originalUrl');
      return _urlCache[originalUrl]!;
    }
    
    // Add cache-busting parameter
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final urlWithTimestamp = originalUrl.contains('?') 
        ? '$originalUrl&t=$timestamp' 
        : '$originalUrl?t=$timestamp';
    
    // Cache the URL for future use
    _urlCache[originalUrl] = urlWithTimestamp;
    
    // For web, we return the original URL with timestamp
    // The video player will handle the headers separately
    return urlWithTimestamp;
  }
  
  // Clear the URL cache
  static void clearCache() {
    _urlCache.clear();
  }
} 