import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';

class UserSearchScreen extends StatefulWidget {
  const UserSearchScreen({super.key});

  @override
  State<UserSearchScreen> createState() => _UserSearchScreenState();
}

class _UserSearchScreenState extends State<UserSearchScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isLoading = false;
  List<Map<String, dynamic>> _searchResults = [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _searchUsers() async {
    final query = _searchController.text.trim().toLowerCase();
    
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
      });
      return;
    }

    setState(() {
      _searchQuery = query;
      _isLoading = true;
    });

    try {
      // Search for users where username contains the query (case insensitive)
      final querySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('usernameLowerCase', isGreaterThanOrEqualTo: query)
          .where('usernameLowerCase', isLessThanOrEqualTo: query + '\uf8ff')
          .get();

      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      
      if (mounted) {
        setState(() {
          _searchResults = querySnapshot.docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'username': data['username'] as String? ?? 'Anonymous',
              'email': data['email'] as String? ?? '',
              'photoUrl': data['photoURL'] as String?,
              'isCurrentUser': doc.id == currentUserId,
            };
          }).toList();
          _isLoading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error searching users: ${error.toString()}')),
        );
      }
    }
  }

  void _viewUserProfile(String userId) {
    // Navigate back to chat screen and pass the user ID for private messaging
    Navigator.pop(context, userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Search Users'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Search by username',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchResults = [];
                    });
                  },
                ),
              ),
              onSubmitted: (_) => _searchUsers(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _searchUsers,
                child: const Text('Search'),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_searchResults.isEmpty && _searchQuery.isNotEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.person_search, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    'No users found matching "$_searchQuery"',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            )
          else if (_searchQuery.isNotEmpty)
            Expanded(
              child: ListView.builder(
                itemCount: _searchResults.length,
                itemBuilder: (context, index) {
                  final user = _searchResults[index];
                  final username = user['username'] as String;
                  
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    elevation: 1,
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: user['photoUrl'] != null
                            ? NetworkImage(user['photoUrl'] as String)
                            : null,
                        backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                        child: user['photoUrl'] == null
                            ? Text(
                                username.isNotEmpty ? username[0].toUpperCase() : '?',
                                style: TextStyle(color: AppTheme.primaryColor),
                              )
                            : null,
                      ),
                      title: Text(username),
                      subtitle: Text(user['email'] as String),
                      trailing: user['isCurrentUser']
                          ? const Chip(
                              label: Text('You'),
                              backgroundColor: Colors.grey,
                              labelStyle: TextStyle(color: Colors.white),
                            )
                          : ElevatedButton.icon(
                              icon: const Icon(Icons.message, size: 16),
                              label: const Text('Chat'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.lightAccentColor,
                                foregroundColor: Colors.white,
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _viewUserProfile(user['id'] as String),
                            ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
} 