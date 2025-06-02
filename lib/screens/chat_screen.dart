import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_chat_reactions/flutter_chat_reactions.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../services/chat_service.dart';
import '../models/message.dart';
import '../models/chat_user.dart';
import '../theme/app_theme.dart';
import 'profile_screen.dart';
import 'user_search_screen.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  final ChatService _chatService = ChatService();
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

  // Default reaction emojis
  final List<String> _defaultReactions = ['👍', '❤️', '😂', '😮', '😢', '😡'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(_handleTabChange);
    _chatService.saveUserData(); // Update user data
    _loadRecentContacts();
    
    // Listen for text changes to enable/disable send button
    _messageController.addListener(_updateSendButtonState);
  }

  void _handleTabChange() {
    // Force update UI when tab changes to ensure input visibility
    setState(() {});
    
    if (_tabController.index == 1) {
      // When switching to private chat tab, load recent contacts
      _loadRecentContacts();
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
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Search error: $e')),
      );
    }
  }

  // Send a message
  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    try {
      if (_tabController.index == 0) {
        // Send public message
        await _chatService.sendMessage(
          text: text,
          isPublic: true,
          replyToMessageId: _replyToMessage?.id,
          replyToText: _replyToMessage?.text,
          replyToSenderName: _replyToMessage?.senderName,
        );
      } else if (_selectedUser != null) {
        // Send private message
        await _chatService.sendMessage(
          text: text,
          isPublic: false,
          receiverId: _selectedUser!.id,
          replyToMessageId: _replyToMessage?.id,
          replyToText: _replyToMessage?.text,
          replyToSenderName: _replyToMessage?.senderName,
        );
      }
      _messageController.clear();
      // Clear reply state after sending
      setState(() {
        _replyToMessage = null;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending message: $e')),
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
    });
  }

  @override
  Widget build(BuildContext context) {
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
        leading: IconButton(
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
          IconButton(
            icon: const Icon(Icons.person),
            splashRadius: 24,
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfileScreen()),
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
              children: [
                // Public Chat
                _buildPublicChatView(),
                
                // Private Chats
                _selectedUser == null
                    ? _buildContactsList()
                    : _buildPrivateChatView(),
              ],
            ),
          ),
          
          // Reply preview (if replying and should show input)
          if (_replyToMessage != null && showInput)
            _buildReplyPreview(),
          
          // Message input (only if in public tab or user is selected)
          if (showInput)
            _buildMessageInput(),
          
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
  
  Widget _buildMessageList({required bool isPublic, String? userId}) {
    return StreamBuilder<List<Message>>(
      stream: isPublic
          ? _chatService.getPublicMessages()
          : (userId != null ? _chatService.getPrivateMessages(userId) : null),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
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
                Icon(Icons.error_outline, color: AppTheme.errorColor, size: 40),
                const SizedBox(height: 8),
                Text(
                  'Error loading messages',
                  style: TextStyle(color: AppTheme.errorColor),
                ),
                TextButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        final messages = snapshot.data ?? [];
        
        if (messages.isEmpty) {
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

        final currentUserId = _chatService.currentUser?.uid;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          reverse: true,
          itemCount: messages.length,
          itemBuilder: (context, index) {
            final message = messages[index];
            final isMe = message.senderId == currentUserId;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // Wrap message in dismissible for swipe to reply
                  Dismissible(
                    key: Key('message_${message.id}_${DateTime.now().millisecondsSinceEpoch}'),
                    direction: isMe ? DismissDirection.endToStart : DismissDirection.startToEnd,
                    background: _buildSwipeReplyBackground(isMe),
                    confirmDismiss: (_) async {
                      _setReplyMessage(message);
                      return false; // Don't actually dismiss the item
                    },
                    child: GestureDetector(
                      onLongPress: () {
                        _showMessageOptions(message);
                      },
                      child: Row(
                        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (!isMe && isPublic)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0),
                              child: CircleAvatar(
                                radius: 18,
                                backgroundImage: message.senderAvatar.isNotEmpty
                                    ? NetworkImage(message.senderAvatar)
                                    : null,
                                backgroundColor: AppTheme.primaryColor,
                                child: message.senderAvatar.isEmpty
                                    ? Container(
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: AppTheme.metalGradient,
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          message.senderName.isNotEmpty
                                              ? message.senderName[0].toUpperCase()
                                              : '?',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.lightTextColor,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          Flexible(
                            child: Hero(
                              tag: message.id,
              child: Container(
                                constraints: BoxConstraints(
                                  maxWidth: MediaQuery.of(context).size.width * 0.75,
                                ),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                                  gradient: isMe 
                                    ? const LinearGradient(
                                        colors: [Color(0xFF1E2746), Color(0xFF2E3566)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : const LinearGradient(
                                        colors: [Color(0xFF303450), Color(0xFF404461)],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                  borderRadius: BorderRadius.only(
                                    topLeft: const Radius.circular(20),
                                    topRight: const Radius.circular(20),
                                    bottomLeft: Radius.circular(isMe ? 20 : 4),
                                    bottomRight: Radius.circular(isMe ? 4 : 20),
                                  ),
                                  border: Border.all(
                                    color: isMe 
                                      ? AppTheme.accentColor.withOpacity(0.3)
                                      : Colors.transparent,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isMe 
                                        ? AppTheme.accentColor.withOpacity(0.1)
                                        : Colors.black.withOpacity(0.1),
                                      spreadRadius: 0,
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe && isPublic)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 6.0),
                                        child: Text(
                                          message.senderName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: AppTheme.accentColor,
                                            letterSpacing: 0.3,
                                          ),
                                        ),
                                      ),
                                    
                                    // Reply preview
                                    if (message.replyToMessageId != null)
                                      Container(
                                        padding: const EdgeInsets.all(10),
                                        margin: const EdgeInsets.only(bottom: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                                          border: Border.all(
                                            color: AppTheme.accentColor.withOpacity(0.2),
                                            width: 1,
                                          ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                      Text(
                                              message.replyToSenderName ?? 'Someone',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                                                color: AppTheme.accentColor,
                        ),
                      ),
                    Text(
                                              message.replyToText ?? '',
                      style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.primaryTextColor.withOpacity(0.7),
                      ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
                                      ),
                                    
                                    Text(
                                      message.text,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        color: AppTheme.primaryTextColor,
                                        height: 1.3,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        Text(
                                          DateFormat('HH:mm').format(message.timestamp),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppTheme.secondaryTextColor.withOpacity(0.7),
                                          ),
                                        ),
                                        if (isMe)
                                          Padding(
                                            padding: const EdgeInsets.only(left: 4),
                                            child: Icon(
                                              Icons.done_all,
                                              size: 14,
                                              color: AppTheme.accentColor,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  // Reactions
                  if (message.reactions.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(
                        left: isMe ? 0 : 40,
                        right: isMe ? 10 : 0,
                        top: 4,
                      ),
                      child: _buildReactionsDisplay(message),
                    ),
                ],
              ),
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
      padding: const EdgeInsets.all(12),
      color: AppTheme.primaryColor,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.accentColor.withOpacity(0.1),
                  AppTheme.accentColor.withOpacity(0.2),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.reply, size: 18, color: AppTheme.accentColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Reply to ${_replyToMessage?.senderName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentColor,
                    fontSize: 13,
                  ),
                ),
                Text(
                  _replyToMessage?.text ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppTheme.secondaryTextColor,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppTheme.secondaryTextColor),
            onPressed: _cancelReply,
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
      decoration: BoxDecoration(
        color: AppTheme.secondaryBackgroundColor,
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withOpacity(0.1),
            spreadRadius: 1,
            blurRadius: 6,
            offset: const Offset(0, -3),
          ),
        ],
        border: Border(
          top: BorderSide(
            color: AppTheme.accentColor.withOpacity(0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions_outlined,
              color: AppTheme.accentColor,
            ),
            splashRadius: 20,
            onPressed: () {
              setState(() {
                _showEmojiPicker = !_showEmojiPicker;
              });
            },
          ),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
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
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _messageController.text.trim().isEmpty
                  ? const LinearGradient(
                      colors: [Color(0xFF303450), Color(0xFF404461)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : AppTheme.neonGradient,
              boxShadow: _messageController.text.trim().isEmpty
                  ? []
                  : [
                      BoxShadow(
                        color: AppTheme.accentColor.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ],
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: _messageController.text.trim().isEmpty ? null : _sendMessage,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.send_rounded,
                    color: _messageController.text.trim().isEmpty
                        ? AppTheme.secondaryTextColor
                        : AppTheme.lightTextColor,
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

  void _showMessageOptions(Message message) {
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
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _handleReaction(message, emoji);
                  },
                  child: Text(emoji, style: const TextStyle(fontSize: 28)),
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
              _deleteMessage(message);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
  
  // Delete a message
  Future<void> _deleteMessage(Message message) async {
    try {
      // Show loading dialog
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Delete the message
      await _chatService.deleteMessage(message.id);
      
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
    } catch (e) {
      // Close loading dialog
      if (mounted) Navigator.pop(context);
      
      // Show error
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }
} 