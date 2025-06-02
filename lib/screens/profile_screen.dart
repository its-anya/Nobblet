import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/chat_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late String _username;
  late String _email;
  bool _isLoading = false;
  bool _canEditEmail = false;
  final ChatService _chatService = ChatService();
  final user = FirebaseAuth.instance.currentUser;
  
  // Add states for email verification
  String? _pendingEmail;
  bool _isVerificationSent = false;
  bool _isCheckingVerification = false;
  
  @override
  void initState() {
    super.initState();
    _username = user?.displayName ?? '';
    _email = user?.email ?? '';
    
    // Check if the email is a placeholder email (username@nobblet.app)
    if (_email.endsWith('@nobblet.app')) {
      _canEditEmail = true;
    }
  }

  // Add method to send verification email
  Future<void> _sendVerificationEmail(String newEmail) async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Check if email is valid
      if (!_isValidEmail(newEmail)) {
        throw Exception('Please enter a valid email address');
      }
      
      // Check if email already exists
      final emailExists = await _chatService.checkEmailExists(newEmail);
      if (emailExists) {
        throw Exception('Email already in use by another account');
      }
      
      // Use Firebase's built-in verify before update method
      await user?.verifyBeforeUpdateEmail(
        newEmail,
        ActionCodeSettings(
          url: 'https://nobblet.firebaseapp.com/?email=${Uri.encodeComponent(newEmail)}',
          handleCodeInApp: true,
          androidPackageName: 'com.example.nobblet',
          androidInstallApp: true,
          androidMinimumVersion: '12',
          iOSBundleId: 'com.example.nobblet',
        ),
      );
      
      // Store pending email
      _pendingEmail = newEmail;
      _isVerificationSent = true;
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification email has been sent to $newEmail. Please check your inbox to verify.'),
          backgroundColor: Colors.blue[700],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (error) {
      String errorMessage = 'Error sending verification email';
      
      if (error is FirebaseAuthException) {
        switch (error.code) {
          case 'email-already-in-use':
            errorMessage = 'This email address is already registered to another account. Please use a different email.';
            break;
          case 'invalid-email':
            errorMessage = 'Please enter a valid email address.';
            break;
          case 'requires-recent-login':
            errorMessage = 'For security reasons, please log out and log back in before changing your email.';
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
          duration: const Duration(seconds: 4),
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

  // Add method to check if email is verified
  Future<void> _checkEmailVerification() async {
    setState(() {
      _isCheckingVerification = true;
    });
    
    try {
      // Reload user to get the latest status
      await user?.reload();
      final updatedUser = FirebaseAuth.instance.currentUser;
      
      // If email was updated, verification was successful
      if (updatedUser?.email == _pendingEmail) {
        setState(() {
          _email = updatedUser?.email ?? _email;
          _pendingEmail = null;
          _isVerificationSent = false;
        });
        
        // Update user data in Firestore
        await _chatService.saveUserData();
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified and updated successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Still waiting for verification
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email not yet verified. Please check your inbox and click the verification link.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error checking verification: ${error.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() {
        _isCheckingVerification = false;
      });
    }
  }

  Future<void> _updateProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    _formKey.currentState!.save();
    
    // Check if email is being changed
    if (_canEditEmail && user?.email != _email) {
      // If new email is different from pending email or no verification was sent
      if (_email != _pendingEmail || !_isVerificationSent) {
        _sendVerificationEmail(_email);
        return;
      } else if (_pendingEmail != null && _isVerificationSent) {
        // If there's a pending verification but user tries to update anyway
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please verify your new email address before updating your profile.'),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Check Status',
              textColor: Colors.white,
              onPressed: _checkEmailVerification,
            ),
          ),
        );
        return;
      }
    }
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      // Check if username already exists (if username was changed)
      if (user?.displayName != _username) {
        final query = await _chatService.checkUsernameExists(_username);
        if (query) {
          throw Exception('Username already taken. Please choose another username.');
        }
      }
      
      // Update username in Firebase Auth
      await user?.updateDisplayName(_username);
      
      // Update email if changed and allowed
      if (_canEditEmail && user?.email != _email && _email == _pendingEmail) {
        // Since verification is handled separately, proceed with update
        await user?.updateEmail(_email);
        
        // Reset verification state
        setState(() {
          _pendingEmail = null;
          _isVerificationSent = false;
        });
      }
      
      // Update user data in Firestore
      await _chatService.saveUserData();
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      String errorMessage = 'Error updating profile';
      
      if (error is FirebaseAuthException) {
        switch (error.code) {
          case 'email-already-in-use':
            errorMessage = 'This email address is already registered to another account. Please use a different email.';
            break;
          case 'invalid-email':
            errorMessage = 'Please enter a valid email address.';
            break;
          case 'requires-recent-login':
            errorMessage = 'For security reasons, please log out and log back in before changing your email.';
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
          duration: const Duration(seconds: 4),
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

  bool _isValidEmail(String email) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _signOut() async {
    try {
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/');
      }
    } catch (error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error signing out: ${error.toString()}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                const SizedBox(height: 20),
                Center(
                  child: Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: AppTheme.primaryColor.withOpacity(0.1),
                        backgroundImage: user?.photoURL != null 
                            ? NetworkImage(user!.photoURL!) 
                            : null,
                        child: user?.photoURL == null 
                            ? Text(
                                _username.isNotEmpty ? _username[0].toUpperCase() : '?',
                                style: const TextStyle(
                                  fontSize: 50, 
                                  color: AppTheme.primaryColor,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: CircleAvatar(
                          radius: 20,
                          backgroundColor: AppTheme.lightAccentColor,
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt, size: 20),
                            color: Colors.white,
                            onPressed: () {
                              // Implement photo upload functionality
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Photo upload will be available soon!')),
                              );
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                TextFormField(
                  initialValue: _username,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person),
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
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: _pendingEmail ?? _email,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email),
                    hintText: _canEditEmail 
                      ? 'Add your real email address' 
                      : 'Email cannot be changed',
                    suffixIcon: _canEditEmail 
                      ? (_pendingEmail != null && _isVerificationSent 
                          ? Icon(Icons.pending, color: Colors.orange) 
                          : const Icon(Icons.edit, color: AppTheme.accentColor))
                      : null,
                    helperText: _pendingEmail != null && _isVerificationSent
                      ? 'Verification pending for $_pendingEmail'
                      : (_canEditEmail ? 'Add your real email to enable password recovery' : null),
                    helperStyle: _pendingEmail != null && _isVerificationSent
                      ? TextStyle(color: Colors.orange[700], fontWeight: FontWeight.bold)
                      : null,
                  ),
                  readOnly: !_canEditEmail || (_pendingEmail != null && _isVerificationSent),
                  enabled: _canEditEmail && !(_pendingEmail != null && _isVerificationSent),
                  validator: _canEditEmail ? (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter an email address';
                    }
                    if (!_isValidEmail(value.trim())) {
                      return 'Please enter a valid email address';
                    }
                    return null;
                  } : null,
                  onSaved: (value) {
                    if (_canEditEmail && value != null) {
                      _email = value.trim();
                    }
                  },
                ),
                
                // Add email verification UI
                if (_canEditEmail && _pendingEmail != null && _isVerificationSent)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade300),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.blue.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Verification email sent to $_pendingEmail',
                                style: TextStyle(color: Colors.blue.shade700),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Already verified?',
                              style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
                            ),
                            TextButton(
                              onPressed: _isCheckingVerification ? null : _checkEmailVerification,
                              child: _isCheckingVerification
                                ? const SizedBox(
                                    width: 16,
                                    height: 16, 
                                    child: CircularProgressIndicator(strokeWidth: 2)
                                  )
                                : const Text('Check Status'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                
                const SizedBox(height: 30),
                if (_isLoading)
                  const CircularProgressIndicator()
                else
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _updateProfile,
                      child: Text(_canEditEmail && user?.email != _email && (_pendingEmail != _email || !_isVerificationSent) 
                        ? 'Verify Email' 
                        : 'Update Profile'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 