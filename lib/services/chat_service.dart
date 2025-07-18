import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:async/async.dart';
import 'package:flutter/material.dart';
import '../models/message.dart';
import '../models/chat_user.dart';
import 'appwrite_service.dart';

class ChatService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final AppwriteService _appwriteService = AppwriteService(); 

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Get user reference
  CollectionReference get _userCollection => _firestore.collection('users');

  // Get message reference
  CollectionReference get _messagesCollection => _firestore.collection('messages');

  // Save user to Firestore
  Future<void> saveUserData() async {
    try {
      print('Attempting to save user data to Firestore...');
      final user = currentUser;
      if (user != null) {
        // Wait for a moment to ensure auth state is properly propagated
        await Future.delayed(const Duration(milliseconds: 500));
        
        print('Current user ID: ${user.uid}');
        print('Display Name: ${user.displayName}');
        print('Email: ${user.email}');
        
        // First check if user already exists to preserve admin status
        final existingDoc = await _userCollection.doc(user.uid).get();
        final bool isAdmin = existingDoc.exists ? 
            (existingDoc.data() as Map<String, dynamic>)['isAdmin'] ?? false : false;
        
        print('Preserving admin status: $isAdmin');
        
        final username = user.displayName ?? 'User';
        await _userCollection.doc(user.uid).set({
          'username': username,
          'usernameLowerCase': username.toLowerCase(),
          'email': user.email,
          'photoURL': user.photoURL,
          'lastSeen': FieldValue.serverTimestamp(),
          'isOnline': true,
          'userId': user.uid, // Add user ID for easier querying
          'isAdmin': isAdmin, // Preserve admin status
        }, SetOptions(merge: true));
        
        print('User data saved successfully');
      } else {
        print('No current user found when trying to save data');
        throw Exception('No authenticated user found');
      }
    } catch (e, stackTrace) {
      print('Error saving user data:');
      print('Error: $e');
      print('Stack trace: $stackTrace');
      rethrow;
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

  // Send message with optional file attachment
  Future<void> sendMessage({
    required String text,
    required bool isPublic,
    String? receiverId,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderName,
    String? fileId,
    String? fileName,
    String? mimeType,
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
      fileId: fileId,
      fileName: fileName,
      mimeType: mimeType,
    );

    // Convert the message to JSON and add participants array if needed
    final messageData = newMessage.toJson();
    
    // Add participants array for private messages
    if (!isPublic && receiverId != null) {
      messageData['participants'] = [user.uid, receiverId];
    } else if (isPublic) {
      // For public messages, add the sender as a participant
      messageData['participants'] = [user.uid];
    }

    try {
      print('Sending message with data: ${messageData.toString()}');
      await _messagesCollection.add(messageData);
      print('Message sent successfully');
    } catch (e) {
      print('Error sending message: $e');
      throw e; // Re-throw to allow UI to handle the error
    }
  }

  // Upload file and send message
  Future<Message?> uploadFileAndSendMessage({
    required BuildContext context,
    required String text,
    required bool isPublic,
    String? receiverId,
    String? replyToMessageId,
    String? replyToText,
    String? replyToSenderName,
    List<String>? allowedExtensions,
    Function(Message, double, String, bool)? onProgressUpdate,
  }) async {
    // Create temporary placeholder message with progress bar
    final user = currentUser;
    if (user == null) return null;
    
    try {
      // First create a temporary local message for the UI
      final tempMessageId = FirebaseFirestore.instance.collection('messages').doc().id;
      final tempMessage = Message(
        id: tempMessageId,
        senderId: user.uid,
        senderName: user.displayName ?? 'Unknown',
        senderAvatar: user.photoURL ?? '',
        text: text.isEmpty ? 'Uploading file...' : text,
        timestamp: DateTime.now(),
        isPublic: isPublic,
        receiverId: receiverId,
        replyToMessageId: replyToMessageId,
        replyToText: replyToText,
        replyToSenderName: replyToSenderName,
        isUploading: true,
        uploadProgress: 0.0,
      );
      
      // Create a variable to store file info
      Map<String, dynamic>? fileInfo;
      
      // Start the file upload process (don't show snackbar anymore)
      fileInfo = await _appwriteService.uploadFile(
        context: context,
        allowedExtensions: allowedExtensions,
        onProgressUpdate: (progress, timeRemaining, isComplete) {
          // Update the temp message with progress
          if (onProgressUpdate != null) {
            // Create copy of current fileInfo to avoid null issues
            Map<String, dynamic> currentFileInfo = {
              ...fileInfo ?? {},
              'uploadProgress': progress,
              'fileId': fileInfo?['fileId'] ?? '',
              'fileName': fileInfo?['fileName'] ?? 'File',
              'mimeType': fileInfo?['mimeType'] ?? '',
              'size': fileInfo?['size'] ?? 0,
              'formattedSize': fileInfo?['formattedSize'] ?? '0 B',
            };
            
            // Create updated message with current progress
            final updatedMessage = tempMessage.copyWith(
              uploadProgress: progress,
              fileId: currentFileInfo['fileId'],
              fileName: currentFileInfo['fileName'],
              mimeType: currentFileInfo['mimeType'],
              fileSize: currentFileInfo['size'],
              formattedFileSize: currentFileInfo['formattedSize'],
            );
            
            // Pass update to callback
            print("Chat service progress update: ${(progress * 100).toStringAsFixed(1)}%");
            onProgressUpdate(updatedMessage, progress, timeRemaining, isComplete);
          }
        },
      );
      
      if (fileInfo == null) {
        // User cancelled or upload failed
        return null;
      }
      
      // Send the actual message once upload is complete
      final messageData = {
        'senderId': user.uid,
        'senderName': user.displayName ?? 'Unknown',
        'senderAvatar': user.photoURL ?? '',
        'text': text.isEmpty ? 'Shared a file' : text,
        'timestamp': Timestamp.now(),
        'isPublic': isPublic,
        'receiverId': receiverId,
        'replyToMessageId': replyToMessageId,
        'replyToText': replyToText,
        'replyToSenderName': replyToSenderName,
        'fileId': fileInfo['fileId'],
        'fileName': fileInfo['fileName'],
        'mimeType': fileInfo['mimeType'],
        'reactions': {},
      };
      
      // Add participants array for private messages for querying
      if (!isPublic && receiverId != null) {
        messageData['participants'] = [user.uid, receiverId];
      }

      // Send to Firestore
      await _messagesCollection.add(messageData);
      
      // Return final message for UI updates
      return tempMessage.copyWith(
        isUploading: false,
        uploadProgress: 1.0,
        fileId: fileInfo['fileId'],
        fileName: fileInfo['fileName'],
        mimeType: fileInfo['mimeType'],
        fileSize: fileInfo['size'],
        formattedFileSize: fileInfo['formattedSize'],
        text: text.isEmpty ? 'Shared a file' : text,
      );
    } catch (e) {
      // Error handling
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sharing file: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
      return null;
    }
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

  // Check if current user is admin
  Future<bool> isCurrentUserAdmin() async {
    try {
      final user = currentUser;
      if (user == null) {
        print('isCurrentUserAdmin: No current user found');
        return false;
      }
      
      print('isCurrentUserAdmin: Checking admin status for user ID: ${user.uid}');
      final docSnapshot = await _userCollection.doc(user.uid).get();
      if (!docSnapshot.exists) {
        print('isCurrentUserAdmin: User document does not exist');
        return false;
      }
      
      final userData = docSnapshot.data() as Map<String, dynamic>;
      print('isCurrentUserAdmin: User data: $userData');
      final isAdmin = userData['isAdmin'] == true;
      print('isCurrentUserAdmin: Admin status: $isAdmin');
      
      // Update the user document if isAdmin is missing
      if (!userData.containsKey('isAdmin')) {
        await _userCollection.doc(user.uid).update({'isAdmin': false});
      }
      
      return isAdmin;
    } catch (e) {
      print('Error checking admin status: $e');
      return false;
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

  // Report a message for inappropriate content
  Future<void> reportMessage(String messageId, String reason) async {
    final user = currentUser;
    if (user == null) return;

    try {
      // Update the message to mark it as reported
      await _messagesCollection.doc(messageId).update({
        'isReported': true,
        'reports.${user.uid}': {
          'reason': reason,
          'reportedAt': FieldValue.serverTimestamp(),
          'reporterName': user.displayName ?? 'User',
        }
      });
    } catch (e) {
      print('Error reporting message: $e');
      rethrow;
    }
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

  // Delete a message
  Future<void> deleteMessage(String messageId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      // Get the message
      final messageDoc = await _firestore.collection('messages').doc(messageId).get();
      if (!messageDoc.exists) throw Exception('Message not found');
      
      final message = Message.fromMap(messageDoc.data()!, messageDoc.id);
      
      // Ensure the user is the sender of the message
      if (message.senderId != user.uid) {
        throw Exception('You can only delete your own messages');
      }
      
      // Delete the message
      await _firestore.collection('messages').doc(messageId).delete();
      
      // If message has attachments, delete them
      if (message.attachments.isNotEmpty) {
        for (final attachment in message.attachments) {
          try {
            final fileId = attachment.fileId;
            if (fileId != null && fileId.isNotEmpty) {
              await _appwriteService.deleteFile(fileId);
            }
          } catch (e) {
            print('Error deleting attachment: $e');
          }
        }
      }
    } catch (e) {
      print('Error deleting message: $e');
      rethrow;
    }
  }
  
  // Delete a message as admin
  Future<void> deleteMessageAsAdmin(String messageId) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception('No authenticated user found');

      // Verify user is admin
      final isAdmin = await isCurrentUserAdmin();
      if (!isAdmin) {
        throw Exception('Only admins can perform this action');
      }

      // Get the message
      final messageDoc = await _firestore.collection('messages').doc(messageId).get();
      if (!messageDoc.exists) throw Exception('Message not found');
      
      final message = Message.fromMap(messageDoc.data()!, messageDoc.id);
      
      // Delete the message
      await _firestore.collection('messages').doc(messageId).delete();
      
      // If message has attachments, delete them
      if (message.attachments.isNotEmpty) {
        for (final attachment in message.attachments) {
          try {
            final fileId = attachment.fileId;
            if (fileId != null && fileId.isNotEmpty) {
              await _appwriteService.deleteFile(fileId);
            }
          } catch (e) {
            print('Error deleting attachment: $e');
          }
        }
      }
      
      // Log the admin action
      await _firestore.collection('admin_logs').add({
        'action': 'delete_message',
        'adminId': user.uid,
        'messageId': messageId,
        'senderId': message.senderId,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error deleting message as admin: $e');
      rethrow;
    }
  }

  // Manually set admin status for a user
  Future<void> setAdminStatus(String userId, bool isAdmin) async {
    try {
      await _userCollection.doc(userId).update({
        'isAdmin': isAdmin,
      });
      print('Admin status updated successfully for user $userId: $isAdmin');
    } catch (e) {
      print('Error setting admin status: $e');
      rethrow;
    }
  }

  // Ban or unban a user
  Future<void> setBanStatus(String userId, bool isBanned) async {
    try {
      // Update user document
      await _userCollection.doc(userId).update({
        'isBanned': isBanned,
      });
      
      // Also add/remove from banned_users collection
      if (isBanned) {
        // Add to banned users collection
        await _firestore.collection('banned_users').doc(userId).set({
          'userId': userId,
          'bannedAt': FieldValue.serverTimestamp(),
          'bannedBy': currentUser?.uid,
        });
      } else {
        // Remove from banned users collection
        await _firestore.collection('banned_users').doc(userId).delete();
      }
      
      print('Ban status updated successfully for user $userId: $isBanned');
    } catch (e) {
      print('Error setting ban status: $e');
      rethrow;
    }
  }
  
  // Delete a user account
  Future<void> deleteUserAccount(String userId) async {
    try {
      // First, get user data
      final userDoc = await _userCollection.doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User not found');
      }
      
      // Delete all messages sent by this user
      final sentMessagesQuery = await _messagesCollection
          .where('senderId', isEqualTo: userId)
          .get();
          
      for (var doc in sentMessagesQuery.docs) {
        // Delete associated files if needed
        final messageData = doc.data() as Map<String, dynamic>;
        final fileId = messageData['fileId'] as String?;
        if (fileId != null) {
          try {
            await _appwriteService.deleteFile(fileId);
          } catch (e) {
            print('Error deleting file for message ${doc.id}: $e');
            // Continue with message deletion
          }
        }
        
        // Delete the message
        await _messagesCollection.doc(doc.id).delete();
      }
      
      // Delete the user document
      await _userCollection.doc(userId).delete();
      
      // Remove from banned_users if they were banned
      try {
        await _firestore.collection('banned_users').doc(userId).delete();
      } catch (e) {
        // Ignore errors if they weren't in banned_users
      }
      
      print('User account deleted successfully: $userId');
    } catch (e) {
      print('Error deleting user account: $e');
      rethrow;
    }
  }
  
  // Delete all public messages
  Future<void> deleteAllPublicMessages() async {
    try {
      // Get all public messages
      final query = await _messagesCollection
          .where('isPublic', isEqualTo: true)
          .get();
      
      // Delete each message
      for (var doc in query.docs) {
        // Delete associated files if needed
        final messageData = doc.data() as Map<String, dynamic>;
        final fileId = messageData['fileId'] as String?;
        if (fileId != null) {
          try {
            await _appwriteService.deleteFile(fileId);
          } catch (e) {
            print('Error deleting file for message ${doc.id}: $e');
            // Continue with message deletion
          }
        }
        
        // Delete the message
        await _messagesCollection.doc(doc.id).delete();
      }
      
      print('All public messages deleted successfully');
    } catch (e) {
      print('Error deleting all public messages: $e');
      rethrow;
    }
  }
} 