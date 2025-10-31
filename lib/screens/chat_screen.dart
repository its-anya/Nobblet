import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_chat_reactions/flutter_chat_reactions.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'dart:async';
import '../services/chat_service.dart';
import '../models/message.dart';
import '../models/chat_user.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'user_search_screen.dart';
import 'admin_panel_screen.dart';
import '../widgets/message_bubble.dart';
import '../services/appwrite_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/scheduler.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  final ChatService _chatService = ChatService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<ChatUser> _searchResults = [];
  bool _isSearching = false;
  ChatUser? _selectedUser;
  List<ChatUser> _recentContacts = [];
  bool _isLoadingContacts = false;
  bool _canSendMessage = false;
  bool _showEmojiPicker = false;
  Message? _replyToMessage;
  int _selectedTab = 0;
  
  // Use ValueNotifier to avoid rebuilding the entire widget tree
  final ValueNotifier<Map<String, Message>> _uploadingMessagesNotifier = ValueNotifier({});
  
  // Cached stream for public messages to prevent rebuilds
  Stream<List<Message>>? _cachedPublicMessagesStream;
  
  // Map to store private message streams by user ID
  final Map<String, Stream<List<Message>>> _privateMessageStreams = {};

  // Pagination state - public
  final ScrollController _publicScrollController = ScrollController();
  final List<Message> _publicMessagesPaged = [];
  DateTime? _lastPublicStartAfter;
  bool _isFetchingMorePublic = false;
  bool _hasMorePublic = true;

  // Pagination state - private (per user)
  final Map<String, ScrollController> _privateScrollControllers = {};
  final Map<String, List<Message>> _privateMessagesPaged = {};
  final Map<String, DateTime?> _lastPrivateStartAfter = {};
  final Map<String, bool> _isFetchingMorePrivate = {};
  final Map<String, bool> _hasMorePrivate = {};

  // Default reaction emojis
  final List<String> _defaultReactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  // Keep this widget alive when navigating to prevent rebuilds
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _chatService.saveUserData(); // Update user data
    
    // Load data in the background without triggering UI rebuilds
    Future.microtask(() {
      _loadRecentContacts();
      _checkBannedStatus();
    });
    
    // Listen for text changes to enable/disable send button
    _messageController.addListener(_updateSendButtonState);

    // Scroll listener for public chat pagination
    _publicScrollController.addListener(_handlePublicScroll);
  }

  void _handleTabChange() {
    // Only update UI if tab index actually changed
    if (_selectedTab != _tabController.index) {
      setState(() {
        _selectedTab = _tabController.index;
      });
      
      if (_tabController.index == 1) {
        // When switching to private chat tab, load recent contacts
        _loadRecentContacts();
      }
    }
  }

  void _updateSendButtonState() {
    final canSend = _messageController.text.trim().isNotEmpty;
    if (canSend != _canSendMessage) {
      setState(() {
        _canSendMessage = canSend;
      });
    }
  }

  // Ensure a private scroll controller exists and has a listener
  ScrollController _getPrivateScrollController(String userId) {
    if (_privateScrollControllers[userId] != null) return _privateScrollControllers[userId]!;
    final controller = ScrollController();
    controller.addListener(() => _handlePrivateScroll(userId));
    _privateScrollControllers[userId] = controller;
    return controller;
  }

  void _handlePublicScroll() {
    if (!_hasMorePublic || _isFetchingMorePublic) return;
    final position = _publicScrollController.position;
    if (!position.hasPixels || !position.hasContentDimensions) return;
    // With reverse: true, reaching near the visual top corresponds to maxScrollExtent
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMorePublic();
    }
  }

  void _handlePrivateScroll(String userId) {
    if (_hasMorePrivate[userId] == false || _isFetchingMorePrivate[userId] == true) return;
    final controller = _privateScrollControllers[userId];
    if (controller == null) return;
    final position = controller.position;
    if (!position.hasPixels || !position.hasContentDimensions) return;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _loadMorePrivate(userId);
    }
  }

  Future<void> _loadMorePublic() async {
    if (_isFetchingMorePublic || !_hasMorePublic) return;
    setState(() {
      _isFetchingMorePublic = true;
    });

    final oldMax = _publicScrollController.hasClients ? _publicScrollController.position.maxScrollExtent : 0.0;
    try {
      final older = await _chatService.getPublicMessagesPage(startAfter: _lastPublicStartAfter, limit: 50);
      if (older.isEmpty) {
        setState(() {
          _hasMorePublic = false;
          _isFetchingMorePublic = false;
        });
        return;
      }

      setState(() {
        _publicMessagesPaged.addAll(older);
        _lastPublicStartAfter = _publicMessagesPaged.isNotEmpty ? _publicMessagesPaged.last.timestamp : _lastPublicStartAfter;
        _isFetchingMorePublic = false;
      });

      // Preserve scroll position to avoid jump
      if (_publicScrollController.hasClients) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          final newMax = _publicScrollController.position.maxScrollExtent;
          final delta = newMax - oldMax;
          final newPixels = _publicScrollController.position.pixels + delta;
          if (newPixels <= _publicScrollController.position.maxScrollExtent) {
            _publicScrollController.jumpTo(newPixels);
          }
        });
      }
    } catch (_) {
      setState(() {
        _isFetchingMorePublic = false;
      });
    }
  }

  Future<void> _loadMorePrivate(String userId) async {
    if (_isFetchingMorePrivate[userId] == true || _hasMorePrivate[userId] == false) return;
    _isFetchingMorePrivate[userId] = true;
    final controller = _getPrivateScrollController(userId);
    final oldMax = controller.hasClients ? controller.position.maxScrollExtent : 0.0;
    try {
      final older = await _chatService.getPrivateMessagesPage(
        userId,
        startAfter: _lastPrivateStartAfter[userId],
        limit: 50,
      );
      if (older.isEmpty) {
        setState(() {
          _hasMorePrivate[userId] = false;
          _isFetchingMorePrivate[userId] = false;
        });
        return;
      }

      setState(() {
        final list = _privateMessagesPaged[userId] ?? [];
        list.addAll(older);
        _privateMessagesPaged[userId] = list;
        _lastPrivateStartAfter[userId] = list.isNotEmpty ? list.last.timestamp : _lastPrivateStartAfter[userId];
        _isFetchingMorePrivate[userId] = false;
      });

      if (controller.hasClients) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          final newMax = controller.position.maxScrollExtent;
          final delta = newMax - oldMax;
          final newPixels = controller.position.pixels + delta;
          if (newPixels <= controller.position.maxScrollExtent) {
            controller.jumpTo(newPixels);
          }
        });
      }
    } catch (_) {
      setState(() {
        _isFetchingMorePrivate[userId] = false;
      });
    }
  }

  Future<void> _loadRecentContacts() async {
    if (_isLoadingContacts) return;
    
    setState(() {
      _isLoadingContacts = true;
    });
    
    try {
      final contacts = await _chatService.getRecentContacts();
      if (mounted) {
        setState(() {
          _recentContacts = contacts;
          _isLoadingContacts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingContacts = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading contacts: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _messageController.removeListener(_updateSendButtonState);
    _messageController.dispose();
    _searchController.dispose();
    _tabController.removeListener(_handleTabChange);
    _tabController.dispose();
    _uploadingMessagesNotifier.dispose();

    // Dispose scroll controllers
    _publicScrollController.dispose();
    for (final controller in _privateScrollControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  // Search users by username
  Future<void> _searchUsers() async {
    if (_searchController.text.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await _chatService.searchUsers(_searchController.text.trim());
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search error: $e')),
        );
      }
    }
  }

  // Send a message
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    // Clear input field immediately for better UX
    _messageController.clear();
    
    // Clear reply state after sending
    final replyMessage = _replyToMessage;
    setState(() {
      _replyToMessage = null;
      _canSendMessage = false;
    });

    try {
      if (_tabController.index == 0) {
        // Send public message
        await _chatService.sendMessage(
          text: text,
          isPublic: true,
          replyToMessageId: replyMessage?.id,
          replyToText: replyMessage?.text,
          replyToSenderName: replyMessage?.senderName,
        );
      } else if (_selectedUser != null) {
        // Send private message
        await _chatService.sendMessage(
          text: text,
          isPublic: false,
          receiverId: _selectedUser!.id,
          replyToMessageId: replyMessage?.id,
          replyToText: replyMessage?.text,
          replyToSenderName: replyMessage?.senderName,
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
      );
    }
  }

  // Handle file upload progress updates
  void _handleFileUploadProgress(Message message, double progress, String timeRemaining, bool isComplete) {
    // Progress should always be valid now with our custom implementation
    print("File upload progress: ${message.fileName ?? 'File'} - ${(progress * 100).toStringAsFixed(0)}% - $timeRemaining");
    
    // Update the uploading messages map using ValueNotifier
    final currentMessages = Map<String, Message>.from(_uploadingMessagesNotifier.value);
    
    if (isComplete) {
      // Remove from uploading messages once complete
      print("Upload complete for: ${message.fileName ?? 'File'}");
      currentMessages.remove(message.id);
    } else {
      // Update the message with new progress
      final updatedMessage = message.copyWith(
        uploadProgress: progress,
        formattedFileSize: message.formattedFileSize ?? '0 B',
      );
      
      currentMessages[message.id] = updatedMessage;
    }
    
    // Update the notifier value
    _uploadingMessagesNotifier.value = currentMessages;
  }

  // Share a file
  Future<void> _shareFile() async {
    final text = _messageController.text.trim();
    
    try {
      Message? tempMessage;
      
      if (_tabController.index == 0) {
        // Share file in public chat
        tempMessage = await _chatService.uploadFileAndSendMessage(
          context: context,
          text: text,
          isPublic: true,
          replyToMessageId: _replyToMessage?.id,
          replyToText: _replyToMessage?.text,
          replyToSenderName: _replyToMessage?.senderName,
          onProgressUpdate: _handleFileUploadProgress,
        );
      } else if (_selectedUser != null) {
        // Share file in private chat
        tempMessage = await _chatService.uploadFileAndSendMessage(
          context: context,
          text: text,
          isPublic: false,
          receiverId: _selectedUser!.id,
          replyToMessageId: _replyToMessage?.id,
          replyToText: _replyToMessage?.text,
          replyToSenderName: _replyToMessage?.senderName,
          onProgressUpdate: _handleFileUploadProgress,
        );
      }
      
      // Clear message input if upload started
      if (tempMessage != null) {
        _messageController.clear();
        setState(() {
          _replyToMessage = null;
          
          // Add initial message to uploading map if it's still uploading
          if (tempMessage?.isUploading ?? false) {
            _uploadingMessagesNotifier.value[tempMessage!.id] = tempMessage;
          }
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sharing file: $e')),
      );
    }
  }

  // Handle message reaction
  Future<void> _handleReaction(Message message, String emoji) async {
    try {
      // Show loading indicator
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adding reaction...'),
          duration: Duration(seconds: 1),
        ),
      );

      // Check if user already used this reaction
      final currentUserId = _chatService.currentUser?.uid;
      if (currentUserId != null) {
        if (message.reactions.containsKey(currentUserId) && 
            message.reactions[currentUserId] == emoji) {
          // Remove the reaction if same emoji is tapped again
          await _chatService.removeReaction(messageId: message.id);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Reaction removed')),
          );
        } else {
          // Add or update the reaction
          await _chatService.addReaction(messageId: message.id, reaction: emoji);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Added reaction: $emoji')),
          );
        }
      }
    } catch (e) {
      // Handle specific error types
      String errorMessage = 'Error adding reaction';
      
      if (e.toString().contains('permission-denied')) {
        errorMessage = 'Permission denied. Please try again later.';
      } else if (e.toString().contains('not-found')) {
        errorMessage = 'Message not found. It may have been deleted.';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMessage)),
      );
      
      print('Reaction error details: $e');
    }
  }

  // Show who reacted with a specific emoji
  void _showWhoReacted(Message message, String emoji) async {
    try {
      final users = await _chatService.getUsersWhoReacted(message, emoji);
      final currentUserId = _chatService.currentUser?.uid;
      final currentUserReacted = currentUserId != null && 
          message.reactions.containsKey(currentUserId) && 
          message.reactions[currentUserId] == emoji;
      
      if (!mounted) return;
      
      showModalBottomSheet(
        context: context,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        isScrollControlled: true,
        builder: (context) => Container(
          padding: const EdgeInsets.all(20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Text(
                    emoji,
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Reacted by ${users.length} ${users.length == 1 ? 'person' : 'people'}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.lightTextColor,
                      ),
                    ),
                  ),
                  // Remove button if current user reacted
                  if (currentUserReacted)
                    IconButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _removeUserReaction(message);
                      },
                      icon: const Icon(
                        Icons.remove_circle,
                        color: Colors.orange,
                      ),
                      tooltip: 'Remove my reaction',
                    ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Users list
              if (users.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'No users found',
                      style: TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 16,
                      ),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: users.map((user) => ListTile(
                  leading: CircleAvatar(
                    backgroundImage: user.photoURL != null && user.photoURL!.isNotEmpty
                        ? NetworkImage(user.photoURL!)
                        : null,
                    backgroundColor: AppTheme.accentColor,
                    child: user.photoURL == null || user.photoURL!.isEmpty
                        ? Text(
                            user.username.isNotEmpty ? user.username[0].toUpperCase() : 'U',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  title: Text(
                    user.username,
                    style: const TextStyle(
                      color: AppTheme.lightTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: user.email.isNotEmpty && user.email != user.username
                      ? Text(
                          user.email,
                          style: const TextStyle(
                            color: AppTheme.secondaryTextColor,
                            fontSize: 14,
                          ),
                        )
                      : null,
                )).toList(),
                  ),
                ),
              
              const SizedBox(height: 10),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reactions: $e')),
        );
      }
    }
  }

  // Check if current user has reacted to this message
  bool _userHasReacted(Message message) {
    final currentUserId = _chatService.currentUser?.uid;
    return currentUserId != null && message.reactions.containsKey(currentUserId);
  }

  // Remove user's reaction from message
  Future<void> _removeUserReaction(Message message) async {
    try {
      await _chatService.removeReaction(messageId: message.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reaction removed'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error removing reaction: $e')),
      );
    }
  }

  // Set message to reply to
  void _setReplyMessage(Message message) {
    setState(() {
      _replyToMessage = message;
    });
    // Focus the text field
    FocusScope.of(context).requestFocus(FocusNode());
  }

  // Cancel reply
  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
    });
  }

  void _selectUser(ChatUser user) {
    setState(() {
      _selectedUser = user;
      // Initialize pagination state for this user if needed
      _privateMessagesPaged.putIfAbsent(user.id, () => []);
      _lastPrivateStartAfter.putIfAbsent(user.id, () => null);
      _hasMorePrivate.putIfAbsent(user.id, () => true);
      _isFetchingMorePrivate.putIfAbsent(user.id, () => false);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    final theme = Theme.of(context);
    
    // Always show input in PUBLIC tab or when a user is selected in CHATS tab
    final bool showInput = _tabController.index == 0 || _selectedUser != null;
    
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B132B), Color(0xFF1C2541)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        elevation: 8,
        shadowColor: AppTheme.accentColor.withOpacity(0.2),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            bottom: Radius.circular(16),
          ),
        ),
        title: Text(
          _tabController.index == 0 || _selectedUser == null 
              ? 'Nobblet Chat' 
              : _selectedUser!.username,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        leading: (_tabController.index == 1 && _selectedUser != null)
          ? IconButton(
              icon: const Icon(Icons.arrow_back),
              splashRadius: 24,
              onPressed: () {
                setState(() {
                  _selectedUser = null;
                });
              },
            )
          : IconButton(
              icon: const Icon(Icons.menu),
              splashRadius: 24,
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
            ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            splashRadius: 24,
            onPressed: () async {
              final userId = await Navigator.push<String>(
                context,
                MaterialPageRoute(
                  builder: (context) => const UserSearchScreen(),
                  maintainState: true,
                ),
              );
              
              if (userId != null && mounted) {
                try {
                  final users = await _chatService.searchUsers(userId);
                  if (users.isNotEmpty && mounted) {
                    setState(() {
                      _selectedUser = users.first;
                      _tabController.animateTo(1); // Switch to private chat tab with animation
                    });
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error finding user: $e')),
                    );
                  }
                }
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.person),
            splashRadius: 24,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ProfileScreen(),
                  maintainState: true,
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentColor,
          indicatorWeight: 3,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.forum, size: 18, color: _tabController.index == 0 ? AppTheme.accentColor : null),
                  const SizedBox(width: 8),
                  const Text('PUBLIC'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.chat, size: 18, color: _tabController.index == 1 ? AppTheme.accentColor : null),
                  const SizedBox(width: 8),
                  const Text('CHATS'),
                ],
              ),
            ),
          ],
        ),
      ),
      drawer: _buildDrawer(theme),
      body: Column(
        children: [
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Public Chat - Use RepaintBoundary to prevent unnecessary repaints
                RepaintBoundary(
                  child: _buildMessageList(isPublic: true),
                ),
                
                // Private Chats - Use RepaintBoundary to prevent unnecessary repaints
                RepaintBoundary(
                  child: _selectedUser == null
                      ? _buildContactsList()
                      : Column(
                          children: [
                            // User info header with better visibility
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.secondaryColor,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundImage: _selectedUser!.photoURL != null
                                        ? NetworkImage(_selectedUser!.photoURL!)
                                        : null,
                                    backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                                    child: _selectedUser!.photoURL == null
                                        ? Text(
                                            _selectedUser!.username[0].toUpperCase(),
                                            style: TextStyle(color: theme.colorScheme.primary),
                                          )
                                        : null,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedUser!.username,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Container(
                                              width: 8,
                                              height: 8,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: _selectedUser!.isOnline ? Colors.green : Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              _selectedUser!.isOnline ? 'Online' : 'Last seen recently',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: _selectedUser!.isOnline ? Colors.green : Colors.grey,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Back button
                                  IconButton(
                                    icon: const Icon(Icons.arrow_back),
                                    splashRadius: 20,
                                    color: AppTheme.accentColor,
                                    onPressed: () {
                                      setState(() {
                                        _selectedUser = null;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ),
                            // Messages list
                            Expanded(
                              child: _buildMessageList(isPublic: false, userId: _selectedUser!.id),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
          
          // Message input with reply preview (only if in public tab or user is selected)
          if (showInput) 
            Column(
              children: [
                // Reply preview
                if (_replyToMessage != null)
                  _buildReplyPreview(),
                
                // Message input
                _buildMessageInput(),
              ],
            ),
          
          // Emoji picker (only if in public tab or user is selected)
          if (_showEmojiPicker && showInput)
            SizedBox(
              height: 250,
              child: EmojiPicker(
                onEmojiSelected: (category, emoji) {
                  setState(() {
                    _messageController.text = _messageController.text + emoji.emoji;
                    _updateSendButtonState();
                  });
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDrawer(ThemeData theme) {
    return Drawer(
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0B132B), Color(0xFF1A1A2E)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1A1A2E), Color(0xFF0B132B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Color(0xFF00F0FF),
                    blurRadius: 10,
                    offset: Offset(0, 2),
                    spreadRadius: -9,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: AppTheme.accentColor.withOpacity(0.1),
                    backgroundImage: _chatService.currentUser?.photoURL != null
                        ? NetworkImage(_chatService.currentUser!.photoURL!)
                        : null,
                    child: _chatService.currentUser?.photoURL == null
                        ? Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: AppTheme.metalGradient,
                              border: Border.all(
                                color: AppTheme.accentColor.withOpacity(0.5),
                                width: 2,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                (_chatService.currentUser?.displayName?.isNotEmpty ?? false)
                                    ? _chatService.currentUser!.displayName![0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.lightTextColor,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _chatService.currentUser?.displayName ?? 'User',
                    style: const TextStyle(
                      color: AppTheme.lightTextColor,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _chatService.currentUser?.email ?? '',
                    style: TextStyle(
                      color: AppTheme.lightTextColor.withOpacity(0.7),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            _buildDrawerItem(
              icon: Icons.person,
              title: 'Profile',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ProfileScreen()),
                );
              },
            ),
            _buildDrawerItem(
              icon: Icons.search,
              title: 'Find Users',
              onTap: () async {
                Navigator.pop(context);
                final userId = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(builder: (context) => const UserSearchScreen()),
                );
                
                if (userId != null && mounted) {
                  try {
                    final users = await _chatService.searchUsers(userId);
                    if (users.isNotEmpty) {
                      setState(() {
                        _selectedUser = users.first;
                        _tabController.index = 1; // Switch to private chat tab
                      });
                    }
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error finding user: $e')),
                    );
                  }
                }
              },
            ),
            // Admin panel option - only show to admins
            FutureBuilder<bool>(
              future: _chatService.isCurrentUserAdmin(),
              builder: (context, snapshot) {
                // Show loading indicator while checking
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8.0),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                    ),
                  );
                }
                
                // Only show admin panel if user is admin
                if (snapshot.hasData && snapshot.data == true) {
                  return _buildDrawerItem(
                    icon: Icons.admin_panel_settings,
                    title: 'Admin Panel',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const AdminPanelScreen()),
                      );
                    },
                  );
                } else {
                  // Return an empty container if not admin
                  return const SizedBox.shrink();
                }
              },
            ),
            const Divider(
              color: Color(0xFF303451),
              thickness: 1,
              height: 1,
              indent: 16,
              endIndent: 16,
            ),
            _buildDrawerItem(
              icon: Icons.logout,
              title: 'Logout',
              onTap: () async {
                await _chatService.signOut();
                if (mounted) {
                  Navigator.of(context).pushReplacementNamed('/');
                }
              },
              isDestructive: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon, 
    required String title, 
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return ListTile(
      leading: Icon(
        icon, 
        color: isDestructive ? AppTheme.errorColor : AppTheme.accentColor,
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isDestructive ? AppTheme.errorColor : AppTheme.primaryTextColor,
          fontSize: 16,
          letterSpacing: 0.3,
        ),
      ),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      hoverColor: AppTheme.accentColor.withOpacity(0.1),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildPublicChatView() {
    return _buildMessageList(isPublic: true);
  }

  Widget _buildPrivateChatView() {
    final theme = Theme.of(context);
    
    return Column(
      children: [
        // Header with user info
        if (_selectedUser != null)
            Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.background,
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundImage: _selectedUser!.photoURL != null
                        ? NetworkImage(_selectedUser!.photoURL!)
                        : null,
                  backgroundColor: theme.colorScheme.primary.withOpacity(0.1),
                    child: _selectedUser!.photoURL == null
                      ? Text(
                          _selectedUser!.username[0].toUpperCase(),
                          style: TextStyle(color: theme.colorScheme.primary),
                        )
                        : null,
                  ),
                const SizedBox(width: 12),
                  Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _selectedUser!.username,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  Text(
                        _selectedUser!.isOnline ? 'Online' : 'Last seen recently',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _selectedUser!.isOnline ? AppTheme.onlineColor : null,
                        ),
                      ),
                    ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _selectedUser = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            
          // Chat messages
          Expanded(
          child: _buildMessageList(isPublic: false, userId: _selectedUser?.id),
        ),
      ],
    );
  }

  Widget _buildContactsList() {
    return _isLoadingContacts
        ? const Center(child: CircularProgressIndicator())
        : _recentContacts.isEmpty
            ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
                    Icon(Icons.chat, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text('No conversations yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Find someone to chat with'),
                      onPressed: () async {
                        final userId = await Navigator.push<String>(
                          context,
                          MaterialPageRoute(builder: (context) => const UserSearchScreen()),
                        );
                        
                        if (userId != null && mounted) {
                          try {
                            final users = await _chatService.searchUsers(userId);
                            if (users.isNotEmpty) {
                              setState(() {
                                _selectedUser = users.first;
                              });
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Error finding user: $e')),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _loadRecentContacts,
                child: ListView.builder(
                  itemCount: _recentContacts.length,
                            itemBuilder: (context, index) {
                    final contact = _recentContacts[index];
                              return ListTile(
                                leading: CircleAvatar(
                        backgroundImage: contact.photoURL != null
                            ? NetworkImage(contact.photoURL!)
                                    : null,
                        backgroundColor: Colors.teal[100],
                        child: contact.photoURL == null
                            ? Text(
                                contact.username[0].toUpperCase(),
                                style: TextStyle(color: Colors.teal[800]),
                              )
                                    : null,
                                ),
                                title: Text(
                        contact.username,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                      subtitle: Text(
                        contact.isOnline ? 'Online' : 'Last seen recently',
                        style: TextStyle(
                          color: contact.isOnline ? Colors.green : null,
                        ),
                      ),
                      trailing: contact.isOnline
                          ? Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.green,
                              ),
                            )
                          : null,
                      onTap: () => _selectUser(contact),
                              );
                            },
                          ),
              );
  }
  
  // Get stream for messages (with caching to prevent rebuilds)
  Stream<List<Message>> _getMessagesStream(bool isPublic, String? userId) {
    if (isPublic) {
      // Use cached stream for public messages if available
      _cachedPublicMessagesStream ??= _chatService.getPublicMessages();
      return _cachedPublicMessagesStream!;
    } else if (userId != null) {
      // Use cached stream for private messages if available
      if (!_privateMessageStreams.containsKey(userId)) {
        _privateMessageStreams[userId] = _chatService.getPrivateMessages(userId);
      }
      return _privateMessageStreams[userId]!;
    }
    
    // Fallback to empty stream
    return Stream.value([]);
  }

  // Build message list with optimized rendering
  Widget _buildMessageList({bool isPublic = true, String? userId}) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    
    return StreamBuilder<List<Message>>(
      stream: _getMessagesStream(isPublic, userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && _uploadingMessagesNotifier.value.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
            ),
          );
        }
        
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: AppTheme.errorColor, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Error loading messages: ${snapshot.error}',
                  style: const TextStyle(color: AppTheme.errorColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      // Force refresh the streams
                      if (isPublic) {
                        _cachedPublicMessagesStream = null;
                      } else if (userId != null) {
                        _privateMessageStreams.remove(userId);
                      }
                    });
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }
        
        List<Message> messages = snapshot.data ?? [];
        
        // Merge stream messages into paged lists (for realtime + pagination)
        if (isPublic) {
          // Initialize or prepend new messages
          if (_publicMessagesPaged.isEmpty && messages.isNotEmpty) {
            _publicMessagesPaged.clear();
            _publicMessagesPaged.addAll(messages);
            _lastPublicStartAfter = _publicMessagesPaged.isNotEmpty ? _publicMessagesPaged.last.timestamp : null;
            _hasMorePublic = true;
          } else if (messages.isNotEmpty) {
            final existingIds = _publicMessagesPaged.map((m) => m.id).toSet();
            final List<Message> newOnes = [];
            for (final m in messages) {
              if (!existingIds.contains(m.id)) newOnes.add(m);
            }
            if (newOnes.isNotEmpty) {
              _publicMessagesPaged.insertAll(0, newOnes);
            }
            if (_lastPublicStartAfter == null && _publicMessagesPaged.isNotEmpty) {
              _lastPublicStartAfter = _publicMessagesPaged.last.timestamp;
            }
          }
        } else if (userId != null) {
          final current = _privateMessagesPaged[userId] ?? [];
          if (current.isEmpty && messages.isNotEmpty) {
            _privateMessagesPaged[userId] = [...messages];
            _lastPrivateStartAfter[userId] = messages.isNotEmpty ? messages.last.timestamp : null;
            _hasMorePrivate[userId] = true;
          } else if (messages.isNotEmpty) {
            final existingIds = current.map((m) => m.id).toSet();
            final List<Message> newOnes = [];
            for (final m in messages) {
              if (!existingIds.contains(m.id)) newOnes.add(m);
            }
            if (newOnes.isNotEmpty) {
              current.insertAll(0, newOnes);
              _privateMessagesPaged[userId] = current;
            }
            if (_lastPrivateStartAfter[userId] == null && current.isNotEmpty) {
              _lastPrivateStartAfter[userId] = current.last.timestamp;
            }
          }
        }
        
        // Use ValueListenableBuilder for uploading messages to prevent full widget rebuilds
        return ValueListenableBuilder<Map<String, Message>>(
          valueListenable: _uploadingMessagesNotifier,
          builder: (context, uploadingMessages, child) {
            // Base list comes from our paged lists
            final List<Message> base = isPublic
                ? [..._publicMessagesPaged]
                : (userId != null ? [...(_privateMessagesPaged[userId] ?? [])] : <Message>[]);
            final List<Message> allMessages = [...base];
            
            // Add relevant uploading messages
            if (uploadingMessages.isNotEmpty) {
              final uploadingMsgs = uploadingMessages.values.where((msg) {
                if (isPublic) return msg.isPublic;
                return !msg.isPublic && (msg.receiverId == userId || msg.senderId == userId);
              }).toList();
              
              // Add at the beginning (newest messages)
              allMessages.insertAll(0, uploadingMsgs);
            }
            
            if (allMessages.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isPublic ? Icons.forum_outlined : Icons.chat_bubble_outline,
                      color: AppTheme.secondaryTextColor.withOpacity(0.5),
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      isPublic
                          ? 'No messages in public chat yet. Say hello!'
                          : 'No messages with this user yet. Say hello!',
                      style: TextStyle(
                        color: AppTheme.secondaryTextColor,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              );
            }

            return FutureBuilder<bool>(
              future: _chatService.isCurrentUserAdmin(),
              builder: (context, adminSnapshot) {
                final isAdmin = adminSnapshot.data ?? false;
                final currentUserId = _chatService.currentUser?.uid;
                
                return ListView.builder(
                  key: PageStorageKey<String>(isPublic ? 'public_messages' : 'private_$userId'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                  reverse: true,
                  controller: isPublic ? _publicScrollController : (userId != null ? _getPrivateScrollController(userId) : null),
                  itemCount: allMessages.length,
                  itemBuilder: (context, index) {
                    final message = allMessages[index];
                    final isMe = message.senderId == currentUserId;
                    
                    return Dismissible(
                      key: Key('message_${message.id}_${DateTime.now().millisecondsSinceEpoch}'),
                      direction: isMe ? DismissDirection.endToStart : DismissDirection.startToEnd,
                      background: _buildSwipeReplyBackground(isMe),
                      confirmDismiss: (_) async {
                        _setReplyMessage(message);
                        return false; // Don't actually dismiss the item
                      },
                      child: GestureDetector(
                        onLongPress: () {
                          if (!message.isUploading) {  // Don't show options for uploading messages
                            _showMessageOptions(message, isAdmin);
                          }
                        },
                        child: MessageBubble(
                          key: ValueKey(message.id),
                          message: message,
                          isMe: isMe,
                          isAdmin: isAdmin,
                          onReply: (msg) => _setReplyMessage(msg),
                          onReaction: (msg, emoji) => _handleReaction(msg, emoji),
                          onDelete: (isMe || isAdmin) && !message.isUploading ? (msg) => _deleteMessage(msg.id, isAdmin) : null,
                          onFileProgress: message.isUploading ? _handleFileUploadProgress : null,
                          onReactionClick: (msg, emoji) => _showWhoReacted(msg, emoji),
                          currentUserId: currentUserId,
                        ),
                      ),
                    );
                  },
                );
              }
            );
          },
        );
      },
    );
  }

  Widget _buildReactionsDisplay(Message message) {
    // Group reactions by emoji
    final Map<String, int> reactionCounts = {};
    message.reactions.forEach((key, value) {
      reactionCounts[value] = (reactionCounts[value] ?? 0) + 1;
    });

    return Wrap(
      spacing: 6,
      children: reactionCounts.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF303450), Color(0xFF404461)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.accentColor.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentColor.withOpacity(0.1),
                blurRadius: 4,
                spreadRadius: 0,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(entry.key),
              if (entry.value > 1)
                Container(
                  margin: const EdgeInsets.only(left: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    entry.value.toString(),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.accentColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // Build background for swipe to reply gesture
  Widget _buildSwipeReplyBackground(bool isMe) {
    return Container(
      alignment: isMe ? Alignment.centerLeft : Alignment.centerRight,
      padding: EdgeInsets.only(
        left: isMe ? 16.0 : 0,
        right: isMe ? 0 : 16.0,
      ),
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppTheme.accentColor.withOpacity(0.1),
              AppTheme.accentColor.withOpacity(0.2),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppTheme.accentColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isMe) const Icon(Icons.reply, color: AppTheme.accentColor, size: 16),
            if (!isMe) const SizedBox(width: 4),
            const Text(
              'Reply',
              style: TextStyle(
                color: AppTheme.accentColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            if (isMe) const SizedBox(width: 4),
            if (isMe) const Icon(Icons.reply, color: AppTheme.accentColor, size: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyPreview() {
    return Container(
      margin: const EdgeInsets.only(bottom: 0, left: 8, right: 8, top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
          bottomLeft: Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
        border: Border.all(
          color: AppTheme.accentColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply, size: 16, color: AppTheme.accentColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reply to ${_replyToMessage!.senderName}',
                  style: const TextStyle(
                    color: AppTheme.accentColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyToMessage!.text,
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            color: AppTheme.secondaryTextColor,
            splashRadius: 16,
            constraints: const BoxConstraints(maxHeight: 24, maxWidth: 24),
            padding: EdgeInsets.zero,
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Emoji button
          IconButton(
            icon: Icon(
              _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
              color: AppTheme.accentColor,
            ),
            onPressed: () {
              setState(() {
                _showEmojiPicker = !_showEmojiPicker;
              });
              if (!_showEmojiPicker) {
                FocusScope.of(context).requestFocus(FocusNode());
              }
            },
            splashRadius: 20,
          ),
          
          // Attachment button
          IconButton(
            icon: const Icon(Icons.attach_file, color: AppTheme.accentColor),
            onPressed: () async {
              final tempMessage = await _chatService.uploadFileAndSendMessage(
                context: context,
                text: _messageController.text.trim(),
                isPublic: _tabController.index == 0,
                receiverId: _selectedUser?.id,
                replyToMessageId: _replyToMessage?.id,
                replyToText: _replyToMessage?.text,
                replyToSenderName: _replyToMessage?.senderName,
                onProgressUpdate: _handleFileUploadProgress,
              );
              
              if (tempMessage != null) {
                // Clear message input if upload started
                _messageController.clear();
                
                // Clear reply state
                if (_replyToMessage != null) {
                  setState(() {
                    _replyToMessage = null;
                  });
                }
                
                // Add initial message to uploading map if it's still uploading
                if (tempMessage.isUploading) {
                  final currentMessages = Map<String, Message>.from(_uploadingMessagesNotifier.value);
                  currentMessages[tempMessage.id] = tempMessage;
                  _uploadingMessagesNotifier.value = currentMessages;
                }
              }
            },
            splashRadius: 20,
          ),
          
          // Text field
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                color: AppTheme.secondaryColor,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.accentColor.withOpacity(0.1),
                    blurRadius: 4,
                    spreadRadius: 0,
                  ),
                ],
              ),
              child: TextField(
                controller: _messageController,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
                  hintStyle: TextStyle(color: AppTheme.secondaryTextColor.withOpacity(0.7)),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: AppTheme.primaryColor,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(
                      color: AppTheme.accentColor,
                      width: 1.5,
                    ),
                  ),
                ),
                style: const TextStyle(
                  color: AppTheme.primaryTextColor,
                  fontSize: 15,
                ),
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (text) {
                  // Use the ValueNotifier pattern here to avoid rebuilding the entire widget
                  final canSend = text.trim().isNotEmpty;
                  if (canSend != _canSendMessage) {
                    setState(() {
                      _canSendMessage = canSend;
                    });
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
              
          // Send button
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _canSendMessage
                  ? AppTheme.neonGradient
                  : const LinearGradient(
                      colors: [Color(0xFF303450), Color(0xFF404461)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
              boxShadow: _canSendMessage
                  ? [
                      BoxShadow(
                        color: AppTheme.accentColor.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : [],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _canSendMessage ? _sendMessage : null,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.send_rounded,
                    color: _canSendMessage
                        ? AppTheme.lightTextColor
                        : AppTheme.secondaryTextColor,
                    size: 20,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(Message message, bool isAdmin) {
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
              children: _defaultReactions.map((emoji) {
                final currentUserId = _chatService.currentUser?.uid;
                final hasUserReacted = currentUserId != null && 
                    message.reactions.containsKey(currentUserId) && 
                    message.reactions[currentUserId] == emoji;
                
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _handleReaction(message, emoji);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: hasUserReacted 
                        ? BoxDecoration(
                            color: AppTheme.accentColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.accentColor,
                              width: 2,
                            ),
                          )
                        : null,
                    child: Text(
                      emoji, 
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          
          const Divider(height: 1),
          
          // Actions
          ListTile(
            leading: const Icon(Icons.reply),
            title: const Text('Reply'),
            onTap: () {
              Navigator.pop(context);
              _setReplyMessage(message);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy),
            title: const Text('Copy'),
            onTap: () {
              Navigator.pop(context);
              Clipboard.setData(ClipboardData(text: message.text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Message copied to clipboard'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          
          // Remove reaction option - show if user has reacted
          if (_userHasReacted(message))
            ListTile(
              leading: const Icon(Icons.remove_circle, color: Colors.orange),
              title: const Text('Remove Reaction'),
              onTap: () {
                Navigator.pop(context);
                _removeUserReaction(message);
              },
            ),
          if (message.senderId == _chatService.currentUser?.uid)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteMessage(message);
              },
            ),
        ],
      ),
    );
  }

  // Show delete confirmation dialog
  void _confirmDeleteMessage(Message message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Message'),
        content: const Text('This message will be deleted. This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message.id, false);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
  
  // Delete a message
  Future<void> _deleteMessage(String messageId, bool isAdmin) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return const AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text("Deleting message..."),
              ],
            ),
          );
        },
      );

      if (isAdmin) {
        await _chatService.deleteMessageAsAdmin(messageId);
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted as admin'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      } else {
        await _chatService.deleteMessage(messageId);
        Navigator.of(context).pop(); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Message deleted'),
            backgroundColor: AppTheme.successColor,
          ),
        );
      }
    } catch (e) {
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting message: ${e.toString()}'),
          backgroundColor: AppTheme.errorColor,
        ),
      );
    }
  }

  // Check if current user is banned
  Future<void> _checkBannedStatus() async {
    try {
      final currentUser = _chatService.currentUser;
      if (currentUser != null) {
        final userDoc = await _firestore.collection('users').doc(currentUser.uid).get();
        final userData = userDoc.data();
        
        if (userData != null && userData['isBanned'] == true) {
          // User is banned, show message and log them out
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Your account has been banned by an administrator.'),
              backgroundColor: AppTheme.errorColor,
              duration: Duration(seconds: 5),
            ),
          );
          
          // Wait for snackbar to be visible before logging out
          Future.delayed(const Duration(seconds: 2), () {
            _chatService.signOut().then((_) {
              Navigator.of(context).pushReplacementNamed('/login');
            });
          });
        }
      }
    } catch (e) {
      print('Error checking banned status: $e');
    }
  }
} 
