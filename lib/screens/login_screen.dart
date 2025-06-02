import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  String _usernameOrEmail = '';
  String _password = '';
  bool _isLoading = false;
  bool _obscurePassword = true;
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final ChatService _chatService = ChatService();
  
  // Helper function to check if input is an email
  bool _isEmail(String input) {
    return input.contains('@');
  }
  
  // Send password reset email
  Future<void> _sendPasswordResetEmail() async {
    String email = _usernameOrEmail;
    
    if (_usernameOrEmail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email or username')),
      );
      return;
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      if (!_isEmail(_usernameOrEmail)) {
        // It's a username, find the associated email
        final users = await FirebaseFirestore.instance
            .collection('users')
            .where('usernameLowerCase', isEqualTo: _usernameOrEmail.toLowerCase())
            .get();
        
        if (users.docs.isEmpty) {
          throw Exception('No account found with this username');
        }
        
        email = users.docs.first['email'] as String;
      }
      
      await _auth.sendPasswordResetEmail(email: email);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Password reset email sent to $email'),
          backgroundColor: Colors.green[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      String errorMessage = 'Error sending password reset email.';
      
      if (error is FirebaseAuthException) {
        switch (error.code) {
          case 'invalid-email':
            errorMessage = 'Please enter a valid email address.';
            break;
          case 'user-not-found':
            errorMessage = 'No account found with this email. Please check the email or register first.';
            break;
          default:
            errorMessage = error.message ?? 'An authentication error occurred.';
        }
      } else {
        // Handle custom exceptions
        errorMessage = error.toString();
        if (errorMessage.contains('Exception:')) {
          errorMessage = errorMessage.split('Exception:')[1].trim();
        }
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    _formKey.currentState!.save();
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Login with email or username
      final isEmail = _isEmail(_usernameOrEmail);
      
      if (isEmail) {
        // Login with email
        await _auth.signInWithEmailAndPassword(
          email: _usernameOrEmail,
          password: _password,
        );
      } else {
        // Login with username - get user email from Firestore first
        final users = await FirebaseFirestore.instance
            .collection('users')
            .where('usernameLowerCase', isEqualTo: _usernameOrEmail.toLowerCase())
            .get();
        
        if (users.docs.isEmpty) {
          throw Exception('No account found with this username');
        }
        
        final userEmail = users.docs.first['email'] as String;
        
        await _auth.signInWithEmailAndPassword(
          email: userEmail,
          password: _password,
        );
      }
      
      // Save user data to Firestore
      await _chatService.saveUserData();
      
      // Navigate to chat screen after successful auth
      Navigator.of(context).pushReplacementNamed('/chat');
    } catch (error) {
      // Show user-friendly error message
      String errorMessage = 'An error occurred. Please try again.';
      
      if (error is FirebaseAuthException) {
        switch (error.code) {
          case 'invalid-email':
            errorMessage = 'Please enter a valid email address.';
            break;
          case 'user-disabled':
            errorMessage = 'This account has been disabled. Please contact support.';
            break;
          case 'user-not-found':
            errorMessage = 'No account found with this email. Please register first.';
            break;
          case 'wrong-password':
            errorMessage = 'Incorrect password. Please try again or use the forgot password option.';
            break;
          default:
            errorMessage = error.message ?? 'An authentication error occurred.';
        }
      } else {
        errorMessage = error.toString();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }
  
  Future<void> _signInWithGoogle() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Trigger the authentication flow
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in
        return;
      }
      
      // Obtain the auth details from the request
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // Create a new credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      // Sign in to Firebase with the Google credential
      await _auth.signInWithCredential(credential);
      
      // Save user data to Firestore
      await _chatService.saveUserData();
      
      // Check if user needs to set a username (for new Google sign-ins)
      if (_auth.currentUser?.displayName == null || _auth.currentUser!.displayName!.isEmpty) {
        // Navigate to username setup screen
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/username_setup');
        }
      } else {
        // Navigate to chat screen
        Navigator.of(context).pushReplacementNamed('/chat');
      }
    } catch (error) {
      String errorMessage = 'Google sign in failed. Please try again.';
      
      if (error is FirebaseAuthException) {
        switch (error.code) {
          case 'account-exists-with-different-credential':
            errorMessage = 'An account already exists with the same email address but different sign-in credentials. Please sign in using the original method.';
            break;
          case 'invalid-credential':
            errorMessage = 'The authentication credential is invalid. Please try again.';
            break;
          case 'user-disabled':
            errorMessage = 'This user account has been disabled. Please contact support.';
            break;
          case 'user-not-found':
            errorMessage = 'No user found with this Google account. Please try again.';
            break;
          default:
            errorMessage = error.message ?? 'An authentication error occurred.';
        }
      } else {
        errorMessage = error.toString();
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red[700],
          behavior: SnackBarBehavior.floating,
        ),
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
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Logo and Header
                    _buildHeader(),
                    const SizedBox(height: 30),
                    
                    // Auth Card
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
                                'Login',
                                style: TextStyle(
                                  color: AppTheme.lightTextColor,
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 24),
                              
                              // Username/Email Field
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
                                    hintText: 'Username/Email',
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
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value == null || value.trim().isEmpty) {
                                      return 'Please enter a username or email';
                                    }
                                    return null;
                                  },
                                  onSaved: (value) {
                                    _usernameOrEmail = value!.trim();
                                  },
                                ),
                              ),
                              const SizedBox(height: 16),
                              
                              // Password Field
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
                                    hintText: 'Password',
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
                                      Icons.lock_outline,
                                      color: AppTheme.accentColor,
                                    ),
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _obscurePassword
                                            ? Icons.visibility_off
                                            : Icons.visibility,
                                        color: AppTheme.accentColor,
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _obscurePassword = !_obscurePassword;
                                        });
                                      },
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
                                  obscureText: _obscurePassword,
                                  validator: (value) {
                                    if (value == null || value.length < 6) {
                                      return 'Password must be at least 6 characters';
                                    }
                                    return null;
                                  },
                                  onSaved: (value) {
                                    _password = value!;
                                  },
                                ),
                              ),
                              const SizedBox(height: 8),
                              
                              // Forgot Password Link
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: _sendPasswordResetEmail,
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppTheme.accentColor,
                                    padding: EdgeInsets.zero,
                                  ),
                                  child: const Text(
                                    'Forgot Password?',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ),
                              
                              const SizedBox(height: 16),
                              
                              // Login Button
                              if (_isLoading)
                                const Center(
                                  child: CircularProgressIndicator(
                                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentColor),
                                  ),
                                )
                              else
                                _buildPrimaryButton(
                                  text: 'Login',
                                  onPressed: _submitForm,
                                ),
                              
                              const SizedBox(height: 20),
                              
                              // Divider
                              Row(
                                children: [
                                  Expanded(
                                    child: Divider(
                                      color: AppTheme.secondaryTextColor.withOpacity(0.3),
                                      thickness: 1,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    child: Text(
                                      'OR',
                                      style: TextStyle(
                                        color: AppTheme.secondaryTextColor,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Divider(
                                      color: AppTheme.secondaryTextColor.withOpacity(0.3),
                                      thickness: 1,
                                    ),
                                  ),
                                ],
                              ),
                              
                              const SizedBox(height: 20),
                              
                              // Google Sign In Button
                              _buildGoogleSignInButton(),
                              
                              const SizedBox(height: 20),
                              
                              // Create Account
                              Wrap(
                                alignment: WrapAlignment.center,
                                children: [
                                  Text(
                                    'Don\'t have an account? ',
                                    style: TextStyle(
                                      color: AppTheme.secondaryTextColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Navigator.of(context).pushReplacementNamed('/signup');
                                    },
                                    child: const Text(
                                      'Create new account',
                                      style: TextStyle(
                                        color: AppTheme.accentColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                      ),
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
  
  Widget _buildGoogleSignInButton() {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            spreadRadius: -2,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: _signInWithGoogle,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: Image.asset(
          'assets/google_logo.png',
          height: 24,
        ),
        label: const Text(
          'Sign in with Google',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
} 