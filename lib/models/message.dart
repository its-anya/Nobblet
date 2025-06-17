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
  // New fields for file attachments
  final String? fileId;                // Appwrite file ID
  final String? fileName;              // Original file name
  final String? mimeType;              // File MIME type

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
    );
  }

  Map<String, dynamic> toJson() {
    return {
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
    );
  }
} 