import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:cloud_firestore/cloud_firestore.dart';

class ChatUser {
  final String id;
  final String username;
  final String email;
  final String? photoURL;
  final DateTime lastSeen;
  final bool isOnline;
  final bool isAdmin;
  final bool isBanned;

  ChatUser({
    required this.id,
    required this.username,
    required this.email,
    this.photoURL,
    required this.lastSeen,
    required this.isOnline,
    this.isAdmin = false,
    this.isBanned = false,
  });

  factory ChatUser.fromFirebaseUser(auth.User user) {
    return ChatUser(
      id: user.uid,
      username: user.displayName ?? 'User',
      email: user.email ?? '',
      photoURL: user.photoURL,
      lastSeen: DateTime.now(),
      isOnline: true,
      isAdmin: false,
      isBanned: false,
    );
  }

  factory ChatUser.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatUser(
      id: doc.id,
      username: data['username'] ?? 'Anonymous',
      email: data['email'] ?? '',
      photoURL: data['photoURL'],
      lastSeen: (data['lastSeen'] as Timestamp?)?.toDate() ?? DateTime.now(),
      isOnline: data['isOnline'] ?? false,
      isAdmin: data['isAdmin'] ?? false,
      isBanned: data['isBanned'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'email': email,
      'photoURL': photoURL,
      'lastSeen': Timestamp.fromDate(lastSeen),
      'isOnline': isOnline,
      'isAdmin': isAdmin,
      'isBanned': isBanned,
    };
  }
} 