import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../theme/app_theme.dart';
import '../services/chat_service.dart';
import '../models/chat_user.dart';

class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> with SingleTickerProviderStateMixin {
  final ChatService _chatService = ChatService();
  late TabController _tabController;
  bool _isLoading = false;
  bool _isAdmin = false;
  bool _checkingAdminStatus = true;
  
  // Admin stats
  int _totalUsers = 0;
  int _totalMessages = 0;
  int _activeUsersToday = 0;
  
  // User management
  List<DocumentSnapshot> _users = [];
  List<DocumentSnapshot> _filteredUsers = [];
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  
  // Message moderation
  List<DocumentSnapshot> _reportedMessages = [];
  bool _isLoadingReports = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _verifyAdminStatus();
    
    _searchController.addListener(() {
      _filterUsers();
    });
  }

  // Verify that the current user is an admin
  Future<void> _verifyAdminStatus() async {
    setState(() {
      _checkingAdminStatus = true;
    });
    
    try {
      final isAdmin = await _chatService.isCurrentUserAdmin();
      
      if (mounted) {
        setState(() {
          _isAdmin = isAdmin;
          _checkingAdminStatus = false;
        });
        
        if (isAdmin) {
          // If user is admin, load admin data
          _loadAdminData();
        } else {
          // If not admin, show error and navigate back
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Access denied. Admin privileges required.'),
              backgroundColor: Colors.red,
            ),
          );
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkingAdminStatus = false;
          _isAdmin = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error verifying admin status: $e')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAdminData() async {
    // Only proceed if user is admin
    if (!_isAdmin) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Load dashboard stats
      await _loadDashboardStats();
      
      // Load users
      await _loadUsers();
      
      // Load reported content
      await _loadReportedContent();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading admin data: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadDashboardStats() async {
    // Get total users count
    final usersQuery = await FirebaseFirestore.instance.collection('users').count().get();
    _totalUsers = usersQuery.count ?? 0;
    
    // Get total messages count
    final messagesQuery = await FirebaseFirestore.instance.collection('messages').count().get();
    _totalMessages = messagesQuery.count ?? 0;
    
    // Get active users today
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final activeUsersQuery = await FirebaseFirestore.instance
        .collection('users')
        .where('lastSeen', isGreaterThan: Timestamp.fromDate(today))
        .count()
        .get();
    _activeUsersToday = activeUsersQuery.count ?? 0;
  }

  Future<void> _loadUsers() async {
    final query = await FirebaseFirestore.instance
        .collection('users')
        .orderBy('username')
        .limit(100)
        .get();
    
    setState(() {
      _users = query.docs;
      _filteredUsers = query.docs;
    });
  }

  Future<void> _loadReportedContent() async {
    setState(() {
      _isLoadingReports = true;
    });
    
    try {
      // Load messages that have reports
      final query = await FirebaseFirestore.instance
          .collection('messages')
          .where('isReported', isEqualTo: true)
          .get();
      
      setState(() {
        _reportedMessages = query.docs;
        _isLoadingReports = false;
      });
    } catch (e) {
      setState(() {
        _isLoadingReports = false;
      });
      // Handle if reports field doesn't exist yet
      _reportedMessages = [];
    }
  }

  void _filterUsers() {
    final query = _searchController.text.toLowerCase();
    
    if (query.isEmpty) {
      setState(() {
        _filteredUsers = _users;
        _isSearching = false;
      });
      return;
    }
    
    setState(() {
      _isSearching = true;
      _filteredUsers = _users.where((doc) {
        final data = doc.data() as Map<String, dynamic>;
        final username = (data['username'] as String?)?.toLowerCase() ?? '';
        final email = (data['email'] as String?)?.toLowerCase() ?? '';
        final userId = doc.id.toLowerCase();
        
        return username.contains(query) || 
               email.contains(query) || 
               userId.contains(query);
      }).toList();
    });
  }

  Future<void> _toggleAdminStatus(String userId, bool makeAdmin) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .update({'isAdmin': makeAdmin});
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(makeAdmin 
              ? 'User was made an admin successfully' 
              : 'Admin privileges removed'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh user list
      await _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating admin status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .delete();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Message deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh reported content
      await _loadReportedContent();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting message: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _clearReport(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection('messages')
          .doc(messageId)
          .update({'isReported': false});
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Report cleared'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh reported content
      await _loadReportedContent();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error clearing report: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  // Ban or unban a user
  Future<void> _toggleBanStatus(String userId, bool makeBanned) async {
    try {
      await _chatService.setBanStatus(userId, makeBanned);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(makeBanned 
              ? 'User was banned successfully' 
              : 'User was unbanned successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh user list
      await _loadUsers();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating ban status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // Delete a user account
  Future<void> _deleteUserAccount(String userId) async {
    try {
      // Show confirmation dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete User Account'),
          content: const Text(
            'This will permanently delete the user account and all their messages. This action cannot be undone.',
            style: TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('DELETE'),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Delete the user account
      await _chatService.deleteUserAccount(userId);
      
      // Close loading indicator
      if (mounted) Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('User account deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh user list
      await _loadUsers();
    } catch (e) {
      // Close loading indicator if still showing
      if (mounted) Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting user account: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
  
  // Delete all public messages
  Future<void> _deleteAllPublicMessages() async {
    try {
      // Show confirmation dialog
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete All Public Messages'),
          content: const Text(
            'This will permanently delete ALL messages in the public chat. This action cannot be undone.',
            style: TextStyle(color: Colors.red),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCEL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('DELETE ALL'),
            ),
          ],
        ),
      );
      
      if (confirm != true) return;
      
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      // Delete all public messages
      await _chatService.deleteAllPublicMessages();
      
      // Close loading indicator
      if (mounted) Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('All public messages deleted successfully'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Refresh stats
      await _loadDashboardStats();
    } catch (e) {
      // Close loading indicator if still showing
      if (mounted) Navigator.pop(context);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error deleting public messages: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Panel',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF0B132B), Color(0xFF1C2541)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.accentColor,
          indicatorWeight: 3,
          tabs: const [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dashboard, size: 18),
                  SizedBox(width: 8),
                  Text('DASHBOARD'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.people, size: 18),
                  SizedBox(width: 8),
                  Text('USERS'),
                ],
              ),
            ),
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.content_paste, size: 18),
                  SizedBox(width: 8),
                  Text('MODERATION'),
                ],
              ),
            ),
          ],
        ),
      ),
      body: _checkingAdminStatus 
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Verifying admin privileges...')
                ],
              ),
            )
          : _isLoading 
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildDashboardTab(),
                    _buildUsersTab(),
                    _buildModerationTab(),
                  ],
                ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nobblet Analytics Dashboard',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.lightTextColor,
            ),
          ),
          const SizedBox(height: 24),
          
          // Stats cards
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Total Users',
                  value: _totalUsers.toString(),
                  icon: Icons.people,
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  title: 'Total Messages',
                  value: _totalMessages.toString(),
                  icon: Icons.message,
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  title: 'Active Today',
                  value: _activeUsersToday.toString(),
                  icon: Icons.person_pin,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildStatCard(
                  title: 'Reported Content',
                  value: _reportedMessages.length.toString(),
                  icon: Icons.report_problem,
                  color: Colors.red,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          
          // Quick actions
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppTheme.lightTextColor,
            ),
          ),
          const SizedBox(height: 16),
          
          _buildActionButton(
            icon: Icons.refresh,
            label: 'Refresh Data',
            onPressed: _loadAdminData,
          ),
          
          const SizedBox(height: 12),
          _buildActionButton(
            icon: Icons.people,
            label: 'Go to User Management',
            onPressed: () {
              _tabController.animateTo(1);
            },
          ),
          
          const SizedBox(height: 12),
          _buildActionButton(
            icon: Icons.content_paste,
            label: 'Go to Content Moderation',
            onPressed: () {
              _tabController.animateTo(2);
            },
          ),
          
          const SizedBox(height: 12),
          _buildActionButton(
            icon: Icons.delete_forever,
            label: 'Delete All Public Messages',
            onPressed: _deleteAllPublicMessages,
            color: Colors.red,
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: AppTheme.accentColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.secondaryTextColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.lightTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon),
        label: Text(label),
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          backgroundColor: color,
        ),
      ),
    );
  }

  Widget _buildUsersTab() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search users...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
        
        // User list
        Expanded(
          child: _isSearching && _filteredUsers.isEmpty
              ? const Center(child: Text('No users found'))
              : ListView.builder(
                  itemCount: _filteredUsers.length,
                  itemBuilder: (context, index) {
                    final doc = _filteredUsers[index];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final username = data['username'] as String? ?? 'Unknown';
                    final email = data['email'] as String? ?? 'No email';
                    final isAdmin = data['isAdmin'] as bool? ?? false;
                    final photoURL = data['photoURL'] as String?;
                    final isOnline = data['isOnline'] as bool? ?? false;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppTheme.accentColor.withOpacity(0.1),
                          backgroundImage: photoURL != null ? NetworkImage(photoURL) : null,
                          child: photoURL == null
                              ? Text(username[0].toUpperCase())
                              : null,
                        ),
                        title: Row(
                          children: [
                            Text(username),
                            if (isAdmin)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppTheme.accentColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Admin',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(email),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isOnline ? Colors.green : Colors.grey,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                isAdmin ? Icons.admin_panel_settings : Icons.admin_panel_settings_outlined,
                                color: isAdmin ? Colors.red : AppTheme.accentColor,
                              ),
                              onPressed: () {
                                _toggleAdminStatus(doc.id, !isAdmin);
                              },
                              tooltip: isAdmin ? 'Remove admin privileges' : 'Make admin',
                            ),
                          ],
                        ),
                        onTap: () {
                          // Show user details dialog
                          showDialog(
                            context: context,
                            builder: (context) => _buildUserDetailsDialog(doc),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildUserDetailsDialog(DocumentSnapshot userDoc) {
    final data = userDoc.data() as Map<String, dynamic>;
    
    final username = data['username'] as String? ?? 'Unknown';
    final email = data['email'] as String? ?? 'No email';
    final isAdmin = data['isAdmin'] as bool? ?? false;
    final isBanned = data['isBanned'] as bool? ?? false;
    final photoURL = data['photoURL'] as String?;
    final lastSeen = data['lastSeen'] as Timestamp?;
    final userId = userDoc.id;
    
    return AlertDialog(
      title: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppTheme.accentColor.withOpacity(0.1),
            backgroundImage: photoURL != null ? NetworkImage(photoURL) : null,
            child: photoURL == null ? Text(username[0].toUpperCase()) : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              username,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow('User ID', userId),
          const SizedBox(height: 8),
          _buildDetailRow('Email', email),
          const SizedBox(height: 8),
          _buildDetailRow('Admin Status', isAdmin ? 'Admin' : 'Regular User'),
          const SizedBox(height: 8),
          _buildDetailRow('Ban Status', isBanned ? 'Banned' : 'Not Banned', 
            textColor: isBanned ? Colors.red : null),
          const SizedBox(height: 8),
          _buildDetailRow(
            'Last Seen',
            lastSeen != null
                ? '${lastSeen.toDate().day}/${lastSeen.toDate().month}/${lastSeen.toDate().year}, ${lastSeen.toDate().hour}:${lastSeen.toDate().minute.toString().padLeft(2, '0')}'
                : 'Unknown',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop();
          },
          child: const Text('Close'),
        ),
        // Ban/Unban button
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            _toggleBanStatus(userId, !isBanned);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isBanned ? Colors.green : Colors.orange,
          ),
          child: Text(isBanned ? 'Unban User' : 'Ban User'),
        ),
        // Admin toggle button
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            _toggleAdminStatus(userId, !isAdmin);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: isAdmin ? Colors.red : AppTheme.accentColor,
          ),
          child: Text(isAdmin ? 'Remove Admin' : 'Make Admin'),
        ),
        // Delete user button
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            _deleteUserAccount(userId);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red[700],
          ),
          child: const Text('Delete User'),
        ),
      ],
    );
  }

  Widget _buildDetailRow(String label, String value, {Color? textColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: AppTheme.secondaryTextColor,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              color: textColor ?? AppTheme.lightTextColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildModerationTab() {
    return _isLoadingReports
        ? const Center(child: CircularProgressIndicator())
        : _reportedMessages.isEmpty
            ? const Center(child: Text('No reported messages'))
            : ListView.builder(
                itemCount: _reportedMessages.length,
                itemBuilder: (context, index) {
                  final doc = _reportedMessages[index];
                  final data = doc.data() as Map<String, dynamic>;
                  
                  final text = data['text'] as String? ?? '';
                  final senderName = data['senderName'] as String? ?? 'Unknown';
                  final timestamp = data['timestamp'] as Timestamp?;
                  final dateStr = timestamp != null
                      ? '${timestamp.toDate().day}/${timestamp.toDate().month}/${timestamp.toDate().year}'
                      : 'Unknown date';
                  
                  final reports = (data['reports'] as Map<String, dynamic>?) ?? {};
                  final reportCount = reports.length;
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: Colors.red.withOpacity(0.3),
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ListTile(
                          title: Row(
                            children: [
                              Text(senderName),
                              const SizedBox(width: 8),
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            text,
                            style: const TextStyle(fontSize: 16),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '$reportCount reports',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () => _clearReport(doc.id),
                                child: const Text('Ignore Report'),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                onPressed: () => _deleteMessage(doc.id),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                ),
                                child: const Text('Delete Message'),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
  }
} 