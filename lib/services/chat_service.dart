import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:async/async.dart';
import '../models/message.dart';
import '../models/chat_user.dart';

class ChatService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Get user reference
  CollectionReference get _userCollection => _firestore.collection('users');

  // Get message reference
  CollectionReference get _messagesCollection => _firestore.collection('messages');

  // Save user to Firestore
  Future<void> saveUserData() async {
    final user = currentUser;
    if (user != null) {
      final username = user.displayName ?? 'User';
      await _userCollection.doc(user.uid).set({
        'username': username,
        'usernameLowerCase': username.toLowerCase(),
        'email': user.email,
        'photoURL': user.photoURL,
        'lastSeen': FieldValue.serverTimestamp(),
        'isOnline': true,
      }, SetOptions(merge: true));
    }
  }

  // Check if username already exists
  Future<bool> checkUsernameExists(String username) async {
    try {
      // Skip check if it's the current user's username
      if (currentUser?.displayName?.toLowerCase() == username.toLowerCase()) {
        return false;
      }
      
      final query = await _userCollection
          .where('usernameLowerCase', isEqualTo: username.toLowerCase())
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking username: $e');
      return false; // In case of error, allow the operation
    }
  }
  
  // Check if email already exists
  Future<bool> checkEmailExists(String email) async {
    try {
      // Skip check if it's the current user's email
      if (currentUser?.email?.toLowerCase() == email.toLowerCase()) {
        return false;
      }
      
      final query = await _userCollection
          .where('email', isEqualTo: email.toLowerCase())
          .get();
      
      return query.docs.isNotEmpty;
    } catch (e) {
      print('Error checking email: $e');
      return false; // In case of error, allow the operation
    }
  }

  // Update user online status
  Future<void> updateUserStatus(bool isOnline) async {
    final user = currentUser;
    if (user != null) {
      await _userCollection.doc(user.uid).update({
        'isOnline': isOnline,
        'lastSeen': FieldValue.serverTimestamp(),
      });
    }
  }

  // Send message
  Future<void> sendMessage({
    required String text,
    required bool isPublic,
    String? receiverId,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderName,
  }) async {
    final user = currentUser;
    if (user == null) return;

    final newMessage = Message(
      id: '', // Will be set by Firestore
      senderId: user.uid,
      senderName: user.displayName ?? 'User',
      senderAvatar: user.photoURL ?? '',
      text: text,
      timestamp: DateTime.now(),
      isPublic: isPublic,
      receiverId: receiverId,
      replyToMessageId: replyToMessageId,
      replyToText: replyToText,
      replyToSenderName: replyToSenderName,
    );

    // Convert the message to JSON and add participants array if needed
    final messageData = newMessage.toJson();
    
    // Add participants array for private messages
    if (!isPublic && receiverId != null) {
      messageData['participants'] = [user.uid, receiverId];
    }

    await _messagesCollection.add(messageData);
  }

  // Add or update reaction to a message
  Future<void> addReaction({
    required String messageId,
    required String reaction,
  }) async {
    final user = currentUser;
    if (user == null) return;

    try {
      // First check if the message exists and we have permission to access it
      final messageDoc = await _messagesCollection.doc(messageId).get();
      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }
      
      // Use FieldValue for updating map fields (more reliable than direct updates)
      await _messagesCollection.doc(messageId).update({
        'reactions.${user.uid}': reaction,
      });
    } catch (e) {
      print('Error adding reaction: $e');
      rethrow; // Rethrow to allow UI to handle the error
    }
  }

  // Remove reaction from a message
  Future<void> removeReaction({
    required String messageId,
  }) async {
    final user = currentUser;
    if (user == null) return;

    try {
      // First check if the message exists and we have permission to access it
      final messageDoc = await _messagesCollection.doc(messageId).get();
      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }
      
      // Use FieldValue.delete() to remove the field from the map
      await _messagesCollection.doc(messageId).update({
        'reactions.${user.uid}': FieldValue.delete(),
      });
    } catch (e) {
      print('Error removing reaction: $e');
      rethrow; // Rethrow to allow UI to handle the error
    }
  }

  // Get a specific message by ID (for reply feature)
  Future<Message?> getMessageById(String messageId) async {
    try {
      final doc = await _messagesCollection.doc(messageId).get();
      if (doc.exists) {
        return Message.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('Error fetching message: $e');
      return null;
    }
  }

  // Get public messages
  Stream<List<Message>> getPublicMessages() {
    return _messagesCollection
        .where('isPublic', isEqualTo: true)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => Message.fromFirestore(doc))
          .toList();
    });
  }

  // Get private messages between two users
  Stream<List<Message>> getPrivateMessages(String otherUserId) {
    final user = currentUser;
    if (user == null) return Stream.value([]);
    
    // Create a simpler query that doesn't need complex indexes
    // Just query all non-public messages related to these two users
    return _messagesCollection
        .where('isPublic', isEqualTo: false)
        .where('participants', arrayContainsAny: [user.uid, otherUserId])
        .snapshots()
        .map((snapshot) {
          final List<Message> messages = [];
          
          // Filter messages to only include conversations between these two specific users
          for (var doc in snapshot.docs) {
            final msg = Message.fromFirestore(doc);
            if ((msg.senderId == user.uid && msg.receiverId == otherUserId) ||
                (msg.senderId == otherUserId && msg.receiverId == user.uid)) {
              messages.add(msg);
            }
          }
          
          // Sort by timestamp in descending order
          messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
          return messages;
        });
  }

  // Get all users for search
  Stream<List<ChatUser>> getAllUsers() {
    return _userCollection
        .orderBy('username')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => ChatUser.fromFirestore(doc))
          .where((user) => user.id != currentUser?.uid) // Exclude current user
          .toList();
    });
  }

  // Search users by username or userId
  Future<List<ChatUser>> searchUsers(String query) async {
    if (query.isEmpty) {
      return [];
    }
    
    List<ChatUser> results = [];
    
    // First try to find user by ID (exact match)
    try {
      final doc = await _userCollection.doc(query).get();
      if (doc.exists) {
        final user = ChatUser.fromFirestore(doc);
        if (user.id != currentUser?.uid) { // Exclude current user
          results.add(user);
        }
      }
    } catch (e) {
      // Ignore errors when searching by ID
    }
    
    if (results.isNotEmpty) {
      return results;
    }
    
    // If no results by ID, search by username
    final lowerCaseQuery = query.toLowerCase();
    
    // Use the usernameLowerCase field for more efficient search
    final querySnapshot = await _userCollection
        .where('usernameLowerCase', isGreaterThanOrEqualTo: lowerCaseQuery)
        .where('usernameLowerCase', isLessThanOrEqualTo: lowerCaseQuery + '\uf8ff')
        .limit(20)
        .get();

    results = querySnapshot.docs
        .map((doc) => ChatUser.fromFirestore(doc))
        .where((user) => user.id != currentUser?.uid) // Exclude current user
        .toList();

    return results;
  }

  // Sign out user and update status
  Future<void> signOut() async {
    await updateUserStatus(false);
    await _auth.signOut();
  }

  // Get recent chat contacts (users with whom the current user has exchanged messages)
  Future<List<ChatUser>> getRecentContacts() async {
    final user = currentUser;
    if (user == null) return [];
    
    // Get all private messages where this user is either sender or receiver
    final sent = await _messagesCollection
        .where('isPublic', isEqualTo: false)
        .where('senderId', isEqualTo: user.uid)
        .get();
    
    final received = await _messagesCollection
        .where('isPublic', isEqualTo: false)
        .where('receiverId', isEqualTo: user.uid)
        .get();
    
    // Extract unique user IDs from messages
    final uniqueUserIds = <String>{};
    
    // Add recipient IDs from sent messages
    for (var doc in sent.docs) {
      final receiverId = doc['receiverId'] as String?;
      if (receiverId != null) {
        uniqueUserIds.add(receiverId);
      }
    }
    
    // Add sender IDs from received messages
    for (var doc in received.docs) {
      final senderId = doc['senderId'] as String?;
      if (senderId != null) {
        uniqueUserIds.add(senderId);
      }
    }
    
    // Get user details for all unique IDs
    final contacts = <ChatUser>[];
    
    for (final userId in uniqueUserIds) {
      try {
        final userDoc = await _userCollection.doc(userId).get();
        if (userDoc.exists) {
          contacts.add(ChatUser.fromFirestore(userDoc));
        }
      } catch (e) {
        print('Error fetching user $userId: $e');
      }
    }
    
    return contacts;
  }

  // Delete a message (only author can delete their own messages)
  Future<void> deleteMessage(String messageId) async {
    final user = currentUser;
    if (user == null) return;

    try {
      // First check if the message exists
      final messageDoc = await _messagesCollection.doc(messageId).get();
      
      if (!messageDoc.exists) {
        throw Exception('Message not found');
      }
      
      // Check if the user is the message sender
      final messageData = messageDoc.data() as Map<String, dynamic>;
      if (messageData['senderId'] != user.uid) {
        throw Exception('You can only delete your own messages');
      }
      
      // Delete the message
      await _messagesCollection.doc(messageId).delete();
    } catch (e) {
      print('Error deleting message: $e');
      rethrow; // Rethrow to allow UI to handle the error
    }
  }
} 