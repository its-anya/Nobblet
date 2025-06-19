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
import 'package:url_launcher/url_launcher_string.dart';
import 'package:url_launcher/url_launcher.dart';

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
  File? _pdfFile;
  bool _isPdfLoading = false;
  int _pdfTotalPages = 0;
  int _pdfCurrentPage = 0;

  @override
  void initState() {
    super.initState();
    
    // Only initialize media players on non-web platforms
    if (!kIsWeb) {
      if (_appwriteService.isVideoFile(widget.fileName)) {
        _initializeVideoPlayer();
      } else if (_appwriteService.isPdfFile(widget.fileName)) {
        _loadPdf();
      }
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    super.dispose();
  }

  Future<void> _initializeVideoPlayer() async {
    final videoUrl = _appwriteService.getFileViewUrl(widget.fileId);
    _videoController = VideoPlayerController.network(videoUrl);
    
    await _videoController!.initialize();
    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: false,
      looping: false,
      showControls: widget.showControls,
      aspectRatio: _videoController!.value.aspectRatio,
    );
    
    if (mounted) {
      setState(() {
        _isVideoInitialized = true;
      });
    }
  }

  Future<void> _loadPdf() async {
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
                  Icons.image,
                  size: 48,
                  color: Colors.blue.shade300,
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
    if (kIsWeb) {
      // For web, show a placeholder with download button
      return Container(
        width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
        height: widget.height ?? 200,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.grey.shade100,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library,
                size: 64,
                color: Colors.purple.shade300,
              ),
              const SizedBox(height: 8),
              Text(
                widget.fileName,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
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
                label: const Text('Download Video'),
              ),
            ],
          ),
        ),
      );
    }
    
    // For mobile platforms
    if (!_isVideoInitialized) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Chewie(
          controller: _chewieController!,
        ),
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

  Widget _buildDownloadButton(String label) {
    return SizedBox(
      width: double.infinity,
      height: 36,
      child: ElevatedButton.icon(
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
} 