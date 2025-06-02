import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';

class UsernameSetupScreen extends StatefulWidget {
  const UsernameSetupScreen({super.key});

  @override
  State<UsernameSetupScreen> createState() => _UsernameSetupScreenState();
}

class _UsernameSetupScreenState extends State<UsernameSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  String _username = '';
  bool _isLoading = false;
  bool _isCheckingUsername = false;
  final ChatService _chatService = ChatService();

  Future<bool> _isUsernameTaken(String username) async {
    try {
      final query = await _chatService.checkUsernameExists(username);
      return query;
    } catch (e) {
      return false; // In case of error, allow user to try
    }
  }

  Future<void> _submitUsername() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    _formKey.currentState!.save();
    
    // Check if username already exists
    setState(() {
      _isCheckingUsername = true;
    });
    
    final isUsernameTaken = await _isUsernameTaken(_username);
    
    if (isUsernameTaken) {
      setState(() {
        _isCheckingUsername = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Username already taken. Please choose another username.')),
      );
      return;
    }
    
    setState(() {
      _isCheckingUsername = false;
      _isLoading = true;
    });
    
    try {
      // Update user profile with username
      await _chatService.currentUser?.updateDisplayName(_username);
      
      // Save user data to Firestore
      await _chatService.saveUserData();
      
      // Navigate to chat screen
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/chat');
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isSmallScreen = screenWidth < 600;
    final containerWidth = isSmallScreen ? screenWidth * 0.9 : 450.0;
    
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B132B), Color(0xFF1A1A2E)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Container(
                width: containerWidth,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo and Header
                    _buildHeader(),
                    const SizedBox(height: 30),
                    
                    // Username Card
                    Card(
                      elevation: 12,
                      shadowColor: AppTheme.accentColor.withOpacity(0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(24),
                        side: BorderSide(
                          color: AppTheme.accentColor.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1C2541), Color(0xFF0B132B)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accentColor.withOpacity(0.1),
                              blurRadius: 12,
                              spreadRadius: -3,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Title
                              const Text(
                                'Set Your Username',
                                style: TextStyle(
                                  color: AppTheme.lightTextColor,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              
                              const Text(
                                'Choose a unique username for your Nobblet account',
                                style: TextStyle(
                                  color: AppTheme.secondaryTextColor,
                                  fontSize: 14,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              
                              const SizedBox(height: 24),
                              
                              // Username Field
                              Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.accentColor.withOpacity(0.1),
                                      blurRadius: 8,
                                      spreadRadius: -2,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: TextFormField(
                                  decoration: InputDecoration(
                                    hintText: 'Username',
                                    hintStyle: TextStyle(
                                      color: AppTheme.primaryTextColor.withOpacity(0.5),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide.none,
                                    ),
                                    fillColor: const Color(0xFF1C2541),
                                    filled: true,
                                    prefixIcon: const Icon(
                                      Icons.person_outline,
                                      color: AppTheme.accentColor,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: BorderSide(
                                        color: AppTheme.accentColor.withOpacity(0.3),
                                        width: 1.5,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: AppTheme.accentColor,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  style: const TextStyle(
                                    color: AppTheme.primaryTextColor,
                                    fontSize: 16,
                                  ),
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter a username';
                                    }
                                    return null;
                                  },
                                  onSaved: (value) {
                                    _username = value!.trim();
                                  },
                                ),
                              ),
                              const SizedBox(height: 24),
                              
                              // Submit Button
                              if (_isLoading)
                                const Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                                  ),
                                )
                              else if (_isCheckingUsername)
                                Column(
                                  children: [
                                    const CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'Checking username availability...',
                                      style: TextStyle(
                                        color: AppTheme.primaryTextColor.withOpacity(0.7),
                                      ),
                                    ),
                                  ],
                                )
                              else
                                _buildPrimaryButton(
                                  text: 'Continue',
                                  onPressed: _submitUsername,
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
          ),
        ),
      ),
    );
  }
  
  Widget _buildHeader() {
    return Column(
      children: [
        Container(
          width: 90,
          height: 90,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppTheme.neonGradient,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentColor.withOpacity(0.4),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFF0B132B),
              ),
              child: Center(
                child: Text(
                  'N',
                  style: TextStyle(
                    fontSize: 48,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accentColor,
                    shadows: [
                      Shadow(
                        color: AppTheme.accentColor.withOpacity(0.8),
                        blurRadius: 12,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [AppTheme.accentColor, AppTheme.lightAccentColor],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ).createShader(bounds),
          child: const Text(
            'NOBBLET',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 3,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Small Chats. Big Impact.',
          style: TextStyle(
            fontSize: 16,
            color: AppTheme.secondaryTextColor,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
  
  Widget _buildPrimaryButton({required String text, required VoidCallback onPressed}) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.accentColor.withOpacity(0.3),
            blurRadius: 12,
            spreadRadius: -3,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: AppTheme.neonGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
} 