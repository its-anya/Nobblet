import 'package:cloud_firestore/cloud_firestore.dart';

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
    };
  }
} 