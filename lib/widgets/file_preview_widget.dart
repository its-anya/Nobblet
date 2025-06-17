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
    if (_appwriteService.isVideoFile(widget.fileName)) {
      _initializeVideoPlayer();
    } else if (_appwriteService.isPdfFile(widget.fileName)) {
      _loadPdf();
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
    } else {
      return _buildGenericFilePreview();
    }
  }

  Widget _buildImagePreview() {
    final imageUrl = _appwriteService.getFilePreviewUrl(
      widget.fileId,
      width: (widget.width ?? 400).toInt(),
      height: (widget.height ?? 400).toInt(),
    );

    return Container(
      width: widget.width ?? MediaQuery.of(context).size.width * 0.6,
      height: widget.height ?? 200,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withOpacity(0.1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: kIsWeb
          ? Image.network(
              imageUrl,
              fit: BoxFit.contain,
              headers: _appwriteService.getFileHeaders(),
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                print('Image loading error: $error');
                print('Stack trace: $stackTrace');
                print('Failed URL: $imageUrl');
                print('Headers: ${_appwriteService.getFileHeaders()}');
                return Container(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'Failed to load image',
                        style: TextStyle(
                          color: Colors.red[700],
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        error.toString(),
                        style: TextStyle(
                          color: Colors.red[700]?.withOpacity(0.7),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                );
              },
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.contain,
              loadingBuilder: (context, child, loadingProgress) {
                if (loadingProgress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: loadingProgress.expectedTotalBytes != null
                        ? loadingProgress.cumulativeBytesLoaded / loadingProgress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
            ),
      ),
    );
  }

  Widget _buildVideoPreview() {
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
    if (_isPdfLoading) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_pdfFile == null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: const Center(
          child: Text('Unable to load PDF'),
        ),
      );
    }

    return Container(
      width: widget.width,
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
              ),
              child: PDFView(
                filePath: _pdfFile!.path,
                enableSwipe: true,
                swipeHorizontal: true,
                autoSpacing: false,
                pageFling: true,
                pageSnap: true,
                onRender: (pages) {
                  setState(() {
                    _pdfTotalPages = pages!;
                  });
                },
                onPageChanged: (index, _) {
                  setState(() {
                    _pdfCurrentPage = index!;
                  });
                },
              ),
            ),
          ),
          if (widget.showControls && _pdfTotalPages > 0)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(12),
                  bottomRight: Radius.circular(12),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Page ${_pdfCurrentPage + 1} of $_pdfTotalPages',
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
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
    } else if (widget.mimeType.contains('zip') || 
               widget.mimeType.contains('rar') ||
               widget.mimeType.contains('tar')) {
      iconData = Icons.folder_zip;
      iconColor = Colors.amber;
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
        ],
      ),
    );
  }
} 