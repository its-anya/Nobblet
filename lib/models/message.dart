import 'package:cloud_firestore/cloud_firestore.dart';

class MessageAttachment {
  final String fileId;
  final String fileName;
  final String mimeType;
  
  MessageAttachment({
    required this.fileId, 
    required this.fileName, 
    required this.mimeType
  });
}

class Message {
  final String id;
  final String senderId;
  final String senderName;
  final String senderAvatar;
  final String text;
  final DateTime timestamp;
  final bool isPublic;
  final String? receiverId;
  final Map<String, String> reactions;  // User ID to reaction emoji mapping
  final String? replyToMessageId;      // ID of message being replied to
  final String? replyToText;           // Preview text of replied message
  final String? replyToSenderName;     // Name of sender of replied message
  // File attachment fields
  final String? fileId;                // Appwrite file ID
  final String? fileName;              // Original file name
  final String? mimeType;              // File MIME type
  // File upload status fields
  final bool isUploading;              // Whether file is currently uploading
  final double uploadProgress;         // Upload progress (0.0 - 1.0)
  final String? formattedFileSize;     // Human-readable file size
  final int? fileSize;                 // Raw file size in bytes

  Message({
    required this.id,
    required this.senderId,
    required this.senderName,
    required this.senderAvatar,
    required this.text,
    required this.timestamp,
    required this.isPublic,
    this.receiverId,
    this.reactions = const {},
    this.replyToMessageId,
    this.replyToText,
    this.replyToSenderName,
    this.fileId,
    this.fileName,
    this.mimeType,
    this.isUploading = false,
    this.uploadProgress = 0.0,
    this.formattedFileSize,
    this.fileSize,
  });

  factory Message.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    
    // Parse reactions map
    Map<String, String> reactions = {};
    if (data['reactions'] != null) {
      final reactionsData = data['reactions'] as Map<String, dynamic>;
      reactionsData.forEach((key, value) {
        reactions[key] = value.toString();
      });
    }

    return Message(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderAvatar: data['senderAvatar'] ?? '',
      text: data['text'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPublic: data['isPublic'] ?? true,
      receiverId: data['receiverId'],
      reactions: reactions,
      replyToMessageId: data['replyToMessageId'],
      replyToText: data['replyToText'],
      replyToSenderName: data['replyToSenderName'],
      // Parse file attachment data
      fileId: data['fileId'],
      fileName: data['fileName'],
      mimeType: data['mimeType'],
      // Upload status (won't be in Firestore)
      isUploading: data['isUploading'] ?? false,
      uploadProgress: data['uploadProgress']?.toDouble() ?? 0.0,
      formattedFileSize: data['formattedFileSize'],
      fileSize: data['fileSize'],
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'text': text,
      'timestamp': timestamp,
      'isPublic': isPublic,
      'receiverId': receiverId,
      'reactions': reactions,
      'replyToMessageId': replyToMessageId,
      'replyToText': replyToText,
      'replyToSenderName': replyToSenderName,
      // Include file attachment data if present
      'fileId': fileId,
      'fileName': fileName, 
      'mimeType': mimeType,
    };
    
    // Only include upload fields for transient messages
    if (isUploading) {
      data['isUploading'] = true;
      data['uploadProgress'] = uploadProgress;
      data['formattedFileSize'] = formattedFileSize;
      data['fileSize'] = fileSize;
    }
    
    return data;
  }
  
  // Helper to check if this message has a file attachment
  bool get hasFile => fileId != null && fileName != null;
  
  // Helper to get attachments (for compatibility with chat_service.dart)
  List<MessageAttachment> get attachments {
    if (fileId != null && fileName != null && mimeType != null) {
      return [MessageAttachment(fileId: fileId!, fileName: fileName!, mimeType: mimeType!)];
    }
    return [];
  }

  // Copy this message with updated values
  Message copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? senderAvatar,
    String? text,
    DateTime? timestamp,
    bool? isPublic,
    String? receiverId,
    Map<String, String>? reactions,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderName,
    String? fileId,
    String? fileName,
    String? mimeType,
    bool? isUploading,
    double? uploadProgress,
    String? formattedFileSize,
    int? fileSize,
  }) {
    return Message(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      text: text ?? this.text,
      timestamp: timestamp ?? this.timestamp,
      isPublic: isPublic ?? this.isPublic,
      receiverId: receiverId ?? this.receiverId,
      reactions: reactions ?? this.reactions,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToText: replyToText ?? this.replyToText,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      isUploading: isUploading ?? this.isUploading,
      uploadProgress: uploadProgress ?? this.uploadProgress,
      formattedFileSize: formattedFileSize ?? this.formattedFileSize,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  factory Message.fromMap(Map<String, dynamic> data, String id) {
    return Message(
      id: id,
      senderId: data['senderId'] ?? '',
      senderName: data['senderName'] ?? 'Unknown',
      senderAvatar: data['senderAvatar'] ?? '',
      text: data['text'] ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isPublic: data['isPublic'] ?? true,
      receiverId: data['receiverId'],
      reactions: (data['reactions'] as Map<String, dynamic>?)?.map(
        (key, value) => MapEntry(key, value.toString()),
      ) ?? {},
      replyToMessageId: data['replyToMessageId'],
      replyToText: data['replyToText'],
      replyToSenderName: data['replyToSenderName'],
      fileId: data['fileId'],
      fileName: data['fileName'],
      mimeType: data['mimeType'],
      isUploading: data['isUploading'] ?? false,
      uploadProgress: data['uploadProgress']?.toDouble() ?? 0.0,
      formattedFileSize: data['formattedFileSize'],
      fileSize: data['fileSize'],
    );
  }
} 