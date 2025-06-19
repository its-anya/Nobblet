import 'package:flutter/material.dart';
import '../models/message.dart';
import '../theme/app_theme.dart';
import '../widgets/file_preview_widget.dart';

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMe;
  final bool isAdmin;
  final Function(Message)? onReply;
  final Function(Message, String)? onReaction;
  final Function(Message)? onDelete;
  
  const MessageBubble({
    Key? key,
    required this.message,
    required this.isMe,
    this.isAdmin = false,
    this.onReply,
    this.onReaction,
    this.onDelete,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar for other users' messages
              if (!isMe) _buildAvatar(),
              if (!isMe) const SizedBox(width: 4),
              
              // Message content
              Flexible(
                child: GestureDetector(
                  onLongPress: () {
                    _showMessageOptions(context);
                  },
                  child: Container(
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.75,
                    ),
                    decoration: BoxDecoration(
                      gradient: isMe 
                        ? AppTheme.neonGradient
                        : LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.darkSecondaryColor,
                              AppTheme.primaryColor.withOpacity(0.9),
                            ],
                          ),
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(16),
                        topRight: const Radius.circular(16),
                        bottomLeft: isMe ? const Radius.circular(16) : const Radius.circular(4),
                        bottomRight: isMe ? const Radius.circular(4) : const Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isMe 
                            ? AppTheme.accentColor.withOpacity(0.2) 
                            : Colors.black.withOpacity(0.1),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Reply preview if applicable
                        if (message.replyToMessageId != null)
                          _buildReplyPreview(context),
                        
                        // File attachment if present
                        if (message.hasFile)
                          _buildFileAttachment(context),
                        
                        // Message text
                        if (message.text.isNotEmpty || !message.hasFile)
                          Padding(
                            padding: EdgeInsets.only(
                              left: 12,
                              right: 12,
                              top: message.replyToMessageId != null ? 8 : 12,
                              bottom: 8,
                            ),
                            child: Text(
                              message.text.isEmpty && message.hasFile ? 'Shared a file' : message.text,
                              style: TextStyle(
                                color: isMe ? Colors.white : AppTheme.lightTextColor,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        
                        // Timestamp and name
                        _buildMessageFooter(context),
                      ],
                    ),
                  ),
                ),
              ),
              
              if (isMe) const SizedBox(width: 4),
              // Avatar for my messages
              if (isMe) _buildAvatar(),
            ],
          ),
          
          // Reactions display
          if (message.reactions.isNotEmpty)
            _buildReactions(context),
        ],
      ),
    );
  }
  
  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Reactions row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: ['👍', '❤️', '😂', '😮', '😢', '😡'].map((emoji) {
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    if (onReaction != null) {
                      onReaction!(message, emoji);
                    }
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
                );
              }).toList(),
            ),
          ),
          
          const Divider(height: 1),
          
          // Reply action
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(context);
              if (onReply != null) {
                onReply!(message);
              }
            },
          ),
          
          // Copy action
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: () {
              Navigator.pop(context);
              // Implement copy functionality
            },
          ),
          
          // Delete action - show for my messages or if admin
          if (isMe || isAdmin)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(
                isAdmin && !isMe ? 'Delete (As Admin)' : 'Delete', 
                style: const TextStyle(color: Colors.red)
              ),
              onTap: () {
                Navigator.pop(context);
                if (onDelete != null) {
                  onDelete!(message);
                }
              },
            ),
        ],
      ),
    );
  }
  
  Widget _buildAvatar() {
    return Container(
      width: 32,
      height: 32,
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.secondaryColor,
        image: message.senderAvatar.isNotEmpty
          ? DecorationImage(
              image: NetworkImage(message.senderAvatar),
              fit: BoxFit.cover,
            )
          : null,
      ),
      child: message.senderAvatar.isEmpty
        ? Center(
            child: Text(
              message.senderName.isNotEmpty
                ? message.senderName[0].toUpperCase() 
                : '?',
              style: const TextStyle(
                color: AppTheme.accentColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          )
        : null,
    );
  }
  
  Widget _buildReplyPreview(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8, left: 12, right: 12),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe 
          ? Colors.white.withOpacity(0.12)
          : Colors.black.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isMe ? Colors.white.withOpacity(0.6) : AppTheme.accentColor.withOpacity(0.8),
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.reply,
                size: 14,
                color: AppTheme.accentColor,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  "Reply to ${message.replyToSenderName ?? 'User'}",
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isMe ? Colors.white.withOpacity(0.95) : AppTheme.accentColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            message.replyToText ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: isMe ? Colors.white.withOpacity(0.9) : AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFileAttachment(BuildContext context) {
    if (message.fileId == null || message.fileName == null || message.mimeType == null) {
      return const SizedBox.shrink();
    }
    
    return Container(
      constraints: BoxConstraints(
        maxHeight: 150,
        maxWidth: MediaQuery.of(context).size.width * 0.6,
      ),
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      child: FilePreviewWidget(
        fileId: message.fileId!,
        fileName: message.fileName!,
        mimeType: message.mimeType!,
        showControls: true,
      ),
    );
  }
  
  Widget _buildMessageFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 12, right: 12, bottom: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.senderName,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isMe ? Colors.white.withOpacity(0.9) : AppTheme.accentColor,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '·',
            style: TextStyle(
              color: isMe ? Colors.white.withOpacity(0.7) : AppTheme.secondaryTextColor,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            _formatTimestamp(message.timestamp),
            style: TextStyle(
              fontSize: 11,
              color: isMe ? Colors.white.withOpacity(0.7) : AppTheme.secondaryTextColor,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildReactions(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        top: 4,
        left: isMe ? 40 : 40,
        right: isMe ? 40 : 40,
      ),
      child: Wrap(
        spacing: 4,
        children: message.reactions.entries.map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.secondaryColor.withOpacity(0.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              entry.value,
              style: const TextStyle(fontSize: 12),
            ),
          );
        }).toList(),
      ),
    );
  }
  
  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateToCheck = DateTime(timestamp.year, timestamp.month, timestamp.day);
    
    if (dateToCheck == today) {
      // Today, show time only
      return '${timestamp.hour.toString().padLeft(2, '0')}:${timestamp.minute.toString().padLeft(2, '0')}';
    } else if (dateToCheck == today.subtract(const Duration(days: 1))) {
      // Yesterday
      return 'Yesterday';
    } else if (now.difference(dateToCheck).inDays < 7) {
      // Within the last week
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[timestamp.weekday - 1];
    } else {
      // Older messages
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }
} 