import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../services/appwrite_service.dart';
import '../services/cors_proxy.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dio/dio.dart';
import 'package:app_settings/app_settings.dart';

// Static cache for images and videos
class MediaCache {
  // Cache for processed image URLs
  static final Map<String, String> _imageCache = {};
  
  // Cache for video controllers
  static final Map<String, VideoPlayerController> _videoControllerCache = {};
  static final Map<String, ChewieController> _chewieControllerCache = {};
  
  // Cache for PDF files
  static final Map<String, File> _pdfCache = {};
  
  // Add image URL to cache
  static void cacheImageUrl(String fileId, String url) {
    _imageCache[fileId] = url;
  }
  
  // Get cached image URL
  static String? getCachedImageUrl(String fileId) {
    return _imageCache[fileId];
  }
  
  // Cache video controllers
  static void cacheVideoControllers(String fileId, VideoPlayerController videoController, ChewieController chewieController) {
    _videoControllerCache[fileId] = videoController;
    _chewieControllerCache[fileId] = chewieController;
  }
  
  // Get cached video controllers
  static Map<String, dynamic>? getCachedVideoControllers(String fileId) {
    if (_videoControllerCache.containsKey(fileId) && _chewieControllerCache.containsKey(fileId)) {
      return {
        'videoController': _videoControllerCache[fileId],
        'chewieController': _chewieControllerCache[fileId],
      };
    }
    return null;
  }
  
  // Cache PDF file
  static void cachePdfFile(String fileId, File file) {
    _pdfCache[fileId] = file;
  }
  
  // Get cached PDF file
  static File? getCachedPdfFile(String fileId) {
    return _pdfCache[fileId];
  }
  
  // Clear cache for a specific file
  static void clearCache(String fileId) {
    _imageCache.remove(fileId);
    
    if (_videoControllerCache.containsKey(fileId)) {
      _videoControllerCache[fileId]?.dispose();
      _videoControllerCache.remove(fileId);
    }
    
    if (_chewieControllerCache.containsKey(fileId)) {
      _chewieControllerCache[fileId]?.dispose();
      _chewieControllerCache.remove(fileId);
    }
    
    _pdfCache.remove(fileId);
  }
  
  // Clear all cache
  static void clearAllCache() {
    _imageCache.clear();
    
    _videoControllerCache.forEach((_, controller) => controller.dispose());
    _videoControllerCache.clear();
    
    _chewieControllerCache.forEach((_, controller) => controller.dispose());
    _chewieControllerCache.clear();
    
    _pdfCache.clear();
  }
}

class FilePreviewWidget extends StatefulWidget {
  final String fileId;
  final String fileName;
  final String mimeType;
  final double? width;
  final double? height;
  final bool showControls;

  const FilePreviewWidget({
    Key? key,
    required this.fileId,
    required this.fileName,
    required this.mimeType,
    this.width,
    this.height,
    this.showControls = true,
  }) : super(key: key);

  @override
  State<FilePreviewWidget> createState() => _FilePreviewWidgetState();
}

class _FilePreviewWidgetState extends State<FilePreviewWidget> {
  final AppwriteService _appwriteService = AppwriteService();
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isVideoInitialized = false;
  bool _isVideoPlaying = false;
  File? _pdfFile;
  bool _isPdfLoading = false;
  int _pdfTotalPages = 0;
  int _pdfCurrentPage = 0;
  String? _processedImageUrl;
  bool _isImageLoading = true;

  @override
  void initState() {
    super.initState();
    
    // Initialize media based on type
    if (_appwriteService.isImageFile(widget.fileName)) {
      _loadCachedOrPrepareImageUrl();
    } else if (_appwriteService.isVideoFile(widget.fileName)) {
      _loadCachedOrInitializeVideoPlayer();
    } else if (_appwriteService.isPdfFile(widget.fileName) && !kIsWeb) {
      // PDF loading only for mobile platforms
      _loadCachedOrPreparePdf();
    }
  }

  @override
  void dispose() {
    // Don't dispose controllers if they're cached
    if (_videoController != null && _videoController != MediaCache._videoControllerCache[widget.fileId]) {
      _videoController?.dispose();
    }
    if (_chewieController != null && _chewieController != MediaCache._chewieControllerCache[widget.fileId]) {
      _chewieController?.dispose();
    }
    super.dispose();
  }

  Future<void> _loadCachedOrPrepareImageUrl() async {
    // Check if image URL is already cached
    final cachedUrl = MediaCache.getCachedImageUrl(widget.fileId);
    if (cachedUrl != null) {
      setState(() {
        _processedImageUrl = cachedUrl;
        _isImageLoading = false;
      });
      return;
    }
    
    // If not cached, prepare the URL
    if (kIsWeb) {
      setState(() {
        _isImageLoading = true;
      });
      
      final imageUrl = _appwriteService.getFileViewUrl(widget.fileId);
      final headers = _appwriteService.getFileHeaders();
      
      try {
        // Use CORS proxy to get a data URL for web
        final processedUrl = await CorsProxy.getProxiedImageUrl(imageUrl, headers);
        
        // Cache the processed URL
        MediaCache.cacheImageUrl(widget.fileId, processedUrl);
        
        if (mounted) {
          setState(() {
            _processedImageUrl = processedUrl;
            _isImageLoading = false;
          });
        }
      } catch (e) {
        print('Error processing image URL: $e');
        if (mounted) {
          setState(() {
            _processedImageUrl = imageUrl; // Fallback to original URL
            _isImageLoading = false;
          });
        }
      }
    }
  }

  Future<void> _loadCachedOrInitializeVideoPlayer() async {
    // Check if video controllers are already cached
    final cachedControllers = MediaCache.getCachedVideoControllers(widget.fileId);
    if (cachedControllers != null) {
      setState(() {
        _videoController = cachedControllers['videoController'];
        _chewieController = cachedControllers['chewieController'];
        _isVideoInitialized = true;
      });
      return;
    }
    
    // If not cached, initialize new controllers
    try {
      final videoUrl = _appwriteService.getFileViewUrl(widget.fileId);
      
      // For web platform, use the CORS proxy
      final processedVideoUrl = kIsWeb 
          ? CorsProxy.getProxiedVideoUrl(videoUrl)
          : videoUrl;
      
      print('Initializing video player with URL: $processedVideoUrl');
      
      _videoController = VideoPlayerController.network(
        processedVideoUrl,
        httpHeaders: _appwriteService.getFileHeaders(),
      );
      
      await _videoController!.initialize();
      
      _chewieController = ChewieController(
        videoPlayerController: _videoController!,
        autoPlay: false,
        looping: false,
        showControls: widget.showControls,
        aspectRatio: _videoController!.value.aspectRatio,
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 32),
                const SizedBox(height: 8),
                Text(
                  'Error: $errorMessage',
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        },
        allowFullScreen: true,
        placeholder: const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Cache the controllers
      MediaCache.cacheVideoControllers(widget.fileId, _videoController!, _chewieController!);
      
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }
    } catch (e) {
      print('Error initializing video player: $e');
      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
        });
      }
    }
  }

  Future<void> _loadCachedOrPreparePdf() async {
    // Check if PDF file is already cached
    final cachedPdf = MediaCache.getCachedPdfFile(widget.fileId);
    if (cachedPdf != null) {
      setState(() {
        _pdfFile = cachedPdf;
        _isPdfLoading = false;
      });
      return;
    }
    
    // If not cached, load the PDF
    if (_appwriteService.isPdfFile(widget.fileName)) {
      setState(() {
        _isPdfLoading = true;
      });

      try {
        final url = _appwriteService.getFileViewUrl(widget.fileId);
        final response = await http.get(Uri.parse(url));
        
        final dir = await getTemporaryDirectory();
        final filePath = '${dir.path}/${widget.fileId}.pdf';
        final file = File(filePath);
        
        await file.writeAsBytes(response.bodyBytes);
        
        // Cache the PDF file
        MediaCache.cachePdfFile(widget.fileId, file);
        
        if (mounted) {
          setState(() {
            _pdfFile = file;
            _isPdfLoading = false;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _isPdfLoading = false;
          });
        }
        print('Error loading PDF: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check file type using mime type
    if (_appwriteService.isImageFile(widget.fileName)) {
      return _buildImagePreview();
    } else if (_appwriteService.isVideoFile(widget.fileName)) {
      return _buildVideoPreview();
    } else if (_appwriteService.isPdfFile(widget.fileName)) {
      return _buildPdfPreview();
    } else if (_appwriteService.isZipFile(widget.fileName)) {
      return _buildZipPreview();
    } else {
      return _buildGenericFilePreview();
    }
  }

  Widget _buildImagePreview() {
    // For web platform, use the processed URL
    final imageUrl = kIsWeb && _processedImageUrl != null
        ? _processedImageUrl!
        : _appwriteService.getFileViewUrl(widget.fileId);
    
    if (kIsWeb && _isImageLoading) {
      return Container(
        width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading image...',
              style: const TextStyle(
                fontSize: 14, 
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }
    
    return Container(
      width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
      constraints: BoxConstraints(
        maxHeight: widget.height ?? 250,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade900,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                height: 200,
                memCacheWidth: 800,
                memCacheHeight: 800,
                fadeInDuration: const Duration(milliseconds: 300),
                cacheKey: widget.fileId, // Use fileId as cache key
                maxHeightDiskCache: 1000,
                maxWidthDiskCache: 1000,
                placeholder: (context, url) => const Center(
                  child: CircularProgressIndicator(),
                ),
                errorWidget: (context, url, error) => Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.broken_image,
                      size: 48,
                      color: Colors.red.shade300,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Image failed to load',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _buildDownloadButton('Download Image'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    // Use video preview for all platforms including web
    if (!_isVideoInitialized) {
      return Container(
        width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.black,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading video...',
              style: const TextStyle(
                fontSize: 14, 
                color: Colors.white70,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Add a retry button if video fails to load
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _isVideoInitialized = false;
                });
                _loadCachedOrInitializeVideoPlayer();
              },
              icon: Icon(Icons.refresh, color: Colors.cyanAccent),
              label: Text('Retry', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        ),
      );
    }

    return Container(
      width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(12),
              bottom: Radius.zero,
            ),
            child: AspectRatio(
              aspectRatio: _videoController!.value.aspectRatio,
              child: Chewie(
                controller: _chewieController!,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.5),
              borderRadius: const BorderRadius.vertical(
                top: Radius.zero,
                bottom: Radius.circular(12),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.fileName,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                _buildDownloadButton('Download Video'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfPreview() {
    return Container(
      width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
      constraints: BoxConstraints(
        maxHeight: widget.height ?? 180,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade900,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Container(
                constraints: const BoxConstraints(minHeight: 100),
                child: Icon(
                  Icons.picture_as_pdf,
                  size: 48,
                  color: Colors.red.shade300,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _buildDownloadButton('Download PDF'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZipPreview() {
    return Container(
      width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
      constraints: BoxConstraints(
        maxHeight: widget.height ?? 180,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey.shade900,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Container(
                constraints: const BoxConstraints(minHeight: 100),
                child: Icon(
                  Icons.folder_zip,
                  size: 48,
                  color: Colors.amber.shade700,
                ),
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.fileName,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  _buildDownloadButton('Download ZIP'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGenericFilePreview() {
    // For any other file types
    IconData iconData;
    Color iconColor;

    if (widget.mimeType.contains('audio')) {
      iconData = Icons.audiotrack;
      iconColor = Colors.purple;
    } else if (widget.mimeType.contains('text')) {
      iconData = Icons.description;
      iconColor = Colors.blue;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

    return Container(
      width: widget.width,
      height: widget.height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[200],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            iconData,
            size: 64,
            color: iconColor,
          ),
          const SizedBox(height: 16),
          Text(
            widget.fileName,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (kIsWeb)
            ElevatedButton.icon(
              onPressed: () async {
                final url = _appwriteService.getFileDownloadUrl(widget.fileId);
                try {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                } catch (e) {
                  print('Error launching URL: $e');
                }
              },
              icon: const Icon(Icons.download),
              label: const Text('Download File'),
            ),
        ],
      ),
    );
  }

  Widget _buildDownloadButton(String label) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: ElevatedButton.icon(
        onPressed: () async {
          final url = _appwriteService.getFileDownloadUrl(widget.fileId);
          
          if (kIsWeb) {
            // For web, use browser download
            try {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            } catch (e) {
              print('Error launching URL: $e');
            }
          } else {
            // For mobile, download directly to device
            try {
              // Show downloading indicator
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Downloading file...'))
              );
              
              // Use Dio for better error handling and headers
              final dio = Dio();
              
              // Add authentication headers if needed
              final headers = _appwriteService.getFileHeaders();
              
              // Check storage permission first
              bool hasPermission = false;
              if (Platform.isAndroid) {
                // For Android 13+ (SDK 33+), we need to request specific permissions
                if (await Permission.manageExternalStorage.isGranted) {
                  hasPermission = true;
                } else {
                  // Request storage permissions
                  print('Requesting storage permissions...');
                  
                  // First try with manage external storage (for Android 11+)
                  var manageStatus = await Permission.manageExternalStorage.request();
                  if (manageStatus.isGranted) {
                    hasPermission = true;
                  } else {
                    // Fall back to regular storage permission
                    var storageStatus = await Permission.storage.request();
                    if (storageStatus.isGranted) {
                      hasPermission = true;
                    }
                  }
                  
                  // If still no permission, try with media permissions (Android 13+)
                  if (!hasPermission) {
                    var mediaStatus = await Permission.photos.request();
                    hasPermission = mediaStatus.isGranted;
                  }
                }
                
                if (!hasPermission) {
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Storage permission is required to download files. Please grant permission in app settings.'),
                      backgroundColor: Colors.red,
                      duration: Duration(seconds: 5),
                      action: SnackBarAction(
                        label: 'Settings',
                        onPressed: () async {
                          await openAppSettings();
                        },
                      ),
                    )
                  );
                  return;
                }
              }
              
              // Get the downloads directory
              Directory? directory;
              if (Platform.isAndroid) {
                try {
                  // Try to use the Download directory first
                  directory = Directory('/storage/emulated/0/Download');
                  // Make sure the directory exists
                  if (!await directory.exists()) {
                    await directory.create(recursive: true);
                  }
                } catch (e) {
                  print('Error creating download directory: $e');
                  // Fall back to app's external storage directory
                  directory = await getExternalStorageDirectory();
                  
                  if (directory == null) {
                    // Last resort: use app's documents directory
                    directory = await getApplicationDocumentsDirectory();
                  }
                }
              } else {
                directory = await getApplicationDocumentsDirectory();
              }
              
              if (directory != null) {
                // Create file path
                final filePath = '${directory.path}/${widget.fileName}';
                print('Downloading to: $filePath');
                print('Download URL: $url');
                
                try {
                  // Download file with progress
                  await dio.download(
                    url,
                    filePath,
                    options: Options(
                      headers: headers,
                      receiveTimeout: Duration(minutes: 5),
                    ),
                    onReceiveProgress: (received, total) {
                      if (total != -1) {
                        print('Download progress: ${(received / total * 100).toStringAsFixed(0)}%');
                      }
                    }
                  );
                  
                  // Show success message
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Downloaded to ${directory.path}'),
                      backgroundColor: Colors.green,
                    )
                  );
                } catch (e) {
                  print('Error during download: $e');
                  throw e; // Re-throw to be caught by the outer catch block
                }
              } else {
                throw Exception('Could not access download directory');
              }
            } catch (e) {
              print('Error downloading file: $e');
              if (e is DioException) {
                print('DioError type: ${e.type}');
                print('DioError message: ${e.message}');
                print('DioError response: ${e.response}');
              }
              
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Download failed. Please try again.'),
                  backgroundColor: Colors.red,
                )
              );
            }
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        icon: const Icon(Icons.download, size: 18),
        label: Text(
          label,
          style: const TextStyle(fontSize: 13),
        ),
      ),
    );
  }
} 