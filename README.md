# Nobblet - Modern Chat Application

Nobblet is a feature-rich, cross-platform chat application built with Flutter and Firebase, offering a sleek, futuristic interface with neon accents for an engaging user experience. The app supports both web and mobile platforms, providing seamless communication through public and private messaging.

## Research Paper

For a detailed technical analysis of Nobblet's architecture, implementation, and performance, please read our [research paper](./Nobblet_Research_Paper.md). The paper covers:

- Hybrid architecture design combining Flutter, Firebase, and Appwrite
- Cross-platform file sharing implementation
- Performance benchmarks across different platforms and network conditions
- Security considerations and implementation details
- Future development roadmap

## Features

- **Authentication**
  - Email/password login and registration
  - Username-based login
  - Google Sign-In integration
  - Username setup for new users
  - Password reset functionality

- **Messaging**
  - Public chat rooms
  - Private one-on-one conversations
  - Message reactions
  - Reply to specific messages
  - File sharing (images, videos, PDFs, archives)

- **User Management**
  - User profiles with avatars
  - Online status indicators
  - User search functionality
  - Admin panel for user management

- **Notifications**
  - Push notifications (Firebase Messaging)
  - Platform-specific notification handling (web, iOS, Android)

- **UI/UX**
  - Modern dark theme with neon accents
  - Responsive design for multiple devices
  - Sleek animations and transitions
  - Message bubbles with file previews

## Technologies Used

### Frontend
- **Flutter** - Cross-platform UI framework
- **Dart** - Programming language

### Backend & Services
- **Firebase**
  - Authentication (email/password, Google Sign-In)
  - Firestore (real-time database)
  - Firebase Messaging (push notifications)

- **Appwrite**
  - Storage (file uploads and sharing)
  - Cross-platform file management

### Additional Packages
- `google_sign_in` - Google authentication
- `shared_preferences` - Local storage
- `flutter_local_notifications` - Local notification management
- `file_picker` - File selection
- `dio` - HTTP client for advanced networking

## Project Structure

```
lib/
├── main.dart                  # Entry point with Firebase initialization
├── models/
│   ├── message.dart           # Message model with file support
│   └── chat_user.dart         # User model with roles and status
├── screens/
│   ├── login_screen.dart      # Authentication screens
│   ├── signup_screen.dart
│   ├── username_setup_screen.dart
│   ├── chat_screen.dart       # Main chat interface
│   ├── profile_screen.dart    # User profile management
│   ├── user_search_screen.dart # User discovery
│   └── admin_panel_screen.dart # Admin controls
├── services/
│   ├── chat_service.dart      # Firebase chat operations
│   ├── appwrite_service.dart  # File storage operations
│   └── cors_proxy.dart        # Web CORS handling
└── theme/
    └── app_theme.dart         # App styling and themes
```

## File Sharing Implementation

This project uses Appwrite Storage for handling file uploads and sharing, allowing users to:

- Upload files (images, videos, PDFs, and various document formats)
- View files directly in the chat with appropriate previews
- Download shared files securely

### File Types Supported

- Images (jpg, jpeg, png, gif, webp)
- Videos (mp4, mov, avi, webm)
- Documents (pdf)
- Archives (zip, rar, tar, 7z, gz)

## Cross-Platform Support

- **Web**: Full support with optimized Firebase Web configuration
- **Mobile (iOS/Android)**: Native integration with platform-specific notifications
- **CORS Handling**: Custom proxy for seamless web file operations

## Getting Started

### Prerequisites
- Flutter SDK
- Firebase project with Auth and Firestore enabled
- Appwrite account and project
- Node.js (for maintenance mode functionality)

### Setup Instructions
1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Configure Firebase:
   - Create a Firebase project
   - Enable Authentication (Email/Password and Google Sign-In)
   - Set up Firestore Database
   - Configure Firebase Messaging
4. Configure Appwrite:
   - Create an Appwrite project
   - Set up a storage bucket with appropriate permissions
5. Update configuration files with your Firebase and Appwrite credentials
6. Run the app with `flutter run`

## Maintenance Mode

You can enable maintenance mode when you need to temporarily take down the application for updates or maintenance.

### Enable Maintenance Mode
```bash
npm run maintenance:enable
```

This command will deploy a professionally designed maintenance page to your Firebase hosting, informing users that the site is temporarily down for maintenance.

### Disable Maintenance Mode
```bash
npm run maintenance:disable
```

This command will rebuild your application and restore normal operation.

For more detailed instructions on using maintenance mode, please see the [MAINTENANCE.md](MAINTENANCE.md) guide.

## License

### Proprietary License

Copyright (c) 2025 Nobblet

All rights reserved.

This software and its name "Nobblet" are proprietary. No part of this software, 
including its code, design, functionality, or name may be reproduced, 
distributed, or used to create derivative works or similar applications without 
explicit written permission from the copyright holder.

The name "Nobblet" is protected and cannot be used by any other chat application 
or similar software product.

Unauthorized use, reproduction, or distribution of this software or its name is 
strictly prohibited and may result in legal action.

See the [LICENSE](LICENSE) file for details.


<img src="logo.png" alt="logo"/>
