import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/appwrite_service.dart';
import 'dart:async';

class UploadingFileWidget extends StatefulWidget {
  final Map<String, dynamic> fileInfo;
  final Function(Map<String, dynamic> fileInfo, double progress, String timeRemaining, bool isComplete)? onProgressUpdate;

  const UploadingFileWidget({
    Key? key,
    required this.fileInfo,
    this.onProgressUpdate,
  }) : super(key: key);

  @override
  State<UploadingFileWidget> createState() => _UploadingFileWidgetState();
}

class _UploadingFileWidgetState extends State<UploadingFileWidget> with SingleTickerProviderStateMixin {
  late AppwriteService _appwriteService;
  double progress = 0.0;
  double displayProgress = 0.0; // Visual progress for smooth animation
  String timeRemaining = "Calculating...";
  bool isComplete = false;
  late AnimationController _animationController;
  Timer? _progressAnimationTimer;
  double _lastProgress = -1.0; // Track last progress value

  @override
  void initState() {
    super.initState();
    _appwriteService = AppwriteService();
    
    // Setup animation controller for the loading spinner
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    
    // Update widget with initial progress from fileInfo
    if (widget.fileInfo.containsKey('uploadProgress')) {
      final initialProgress = widget.fileInfo['uploadProgress'] as double? ?? 0.0;
      progress = initialProgress;
      displayProgress = initialProgress;
      _lastProgress = initialProgress;
      isComplete = initialProgress >= 1.0;
    }
    
    // Start progress animation timer
    _startProgressAnimation();
  }
  
  void _startProgressAnimation() {
    // Cancel existing timer if any
    _progressAnimationTimer?.cancel();
    
    // Create new timer that smoothly animates progress
    _progressAnimationTimer = Timer.periodic(const Duration(milliseconds: 33), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      
      setState(() {
        // Smooth animation - move display progress closer to actual progress
        if (displayProgress < progress) {
          // Make the animation smoother with smaller increments
          double stepSize = (progress - displayProgress) / 10;
          // Ensure minimum step size for visible progress
          stepSize = stepSize < 0.002 ? 0.002 : stepSize;
          
          displayProgress += stepSize;
          if (displayProgress > progress) {
            displayProgress = progress;
          }
        }
      });
    });
  }
  
  @override
  void didUpdateWidget(UploadingFileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Update progress when widget is rebuilt with new fileInfo
    if (widget.fileInfo.containsKey('uploadProgress')) {
      final newProgress = widget.fileInfo['uploadProgress'] as double? ?? 0.0;
      
      // Only update if progress actually changed
      if (newProgress != _lastProgress) {
        // Update real progress immediately
        progress = newProgress;
        _lastProgress = newProgress;
        
        // Call updateProgress to update UI
        updateProgress(newProgress, timeRemaining, newProgress >= 1.0);
      }
    }
  }
  
  @override
  void dispose() {
    _progressAnimationTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  // Update the widget state when progress changes
  void updateProgress(double newProgress, String newTimeRemaining, bool complete) {
    if (mounted) {
      setState(() {
        progress = newProgress;
        timeRemaining = newTimeRemaining;
        isComplete = complete;
        
        // If complete, immediately set display progress to 100%
        if (complete) {
          displayProgress = 1.0;
        }
      });
      
      if (widget.onProgressUpdate != null) {
        widget.onProgressUpdate!(widget.fileInfo, newProgress, newTimeRemaining, complete);
      }
    }
  }

  // Get icon based on file type
  IconData _getFileIcon() {
    final String fileName = widget.fileInfo['fileName'];
    return _appwriteService.getIconForFileType(fileName);
  }
  
  // Format percentage for display
  String _formatPercentage() {
    final int percent = (displayProgress * 100).round();
    return '$percent%';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.fileInfo['fileName'] as String;
    final fileSize = widget.fileInfo['formattedSize'] as String;
    final percentText = isComplete ? '100%' : _formatPercentage();
    
    return Container(
      width: MediaQuery.of(context).size.width * 0.7,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: AppTheme.darkSecondaryColor,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // File preview area (top part)
          Container(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // File icon with loading animation
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background container
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppTheme.darkPrimaryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Icon(
                        _getFileIcon(),
                        color: AppTheme.accentColor,
                        size: 24,
                      ),
                    ),
                    // Loading spinner overlay
                    if (!isComplete)
                      RotationTransition(
                        turns: _animationController,
                        child: Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: AppTheme.accentColor.withOpacity(0.6),
                              width: 2,
                              strokeAlign: BorderSide.strokeAlignOutside,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                // File details
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        fileName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // File size
                          Text(
                            fileSize,
                            style: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 12,
                            ),
                          ),
                          // Upload percentage
                          Row(
                            children: [
                              if (!isComplete)
                                SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      AppTheme.accentColor,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 4),
                              Text(
                                percentText,
                                style: TextStyle(
                                  color: isComplete ? AppTheme.successColor : AppTheme.accentColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Progress bar
          Container(
            height: 4,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.darkPrimaryColor,
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: displayProgress,
              child: Container(
                decoration: BoxDecoration(
                  color: isComplete ? AppTheme.successColor : AppTheme.accentColor,
                  boxShadow: [
                    BoxShadow(
                      color: (isComplete ? AppTheme.successColor : AppTheme.accentColor).withOpacity(0.5),
                      blurRadius: 4,
                      spreadRadius: 0,
                    ),
                  ],
                ),
              ),
            ),
          ),
          
          // Time remaining
          if (!isComplete) 
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                timeRemaining,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 12,
                ),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
} 