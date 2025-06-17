# Nobblet - Chat Application with File Sharing

Nobblet is a feature-rich chat application with support for public and private messaging, along with file sharing capabilities.

## Features

- User authentication with Firebase (email/password and Google Sign-In)
- Public and private messaging
- File sharing (images, videos, PDFs and other documents)
- Message reactions
- Reply to messages
- User search and profile management

## Technologies Used

### Firebase
- Authentication
- Firestore Database
- Firebase Messaging

### Appwrite
- Storage (for file sharing)

## File Sharing Implementation

This project uses Appwrite Storage for handling file uploads and sharing. The integration allows users to:

- Upload files (images, videos, PDFs, and other document formats)
- View files directly in the chat
- Download shared files

### Setup Instructions

1. Create an Appwrite account at [appwrite.io](https://appwrite.io/)
2. Create a project (the current project ID is `683932070023292fdf26`)
3. Create a storage bucket (the current bucket ID is `684d55f9000259403eb0`)
4. Configure the storage bucket permissions to allow file uploads and downloads
5. Update the AppwriteService class with your project ID and bucket ID if needed

### File Types Supported

- Images (jpg, jpeg, png, gif, webp)
- Videos (mp4, mov, avi, webm)
- Documents (pdf)
- Other file types can be added by modifying the allowed extensions

## Usage

1. Sign up or log in to the app
2. Navigate to public chat or start a private conversation
3. To share a file:
   - Click the attachment icon in the message composer
   - Select a file from your device
   - Optionally add a message
   - Send the file

## Implementation Details

The file sharing system is implemented using several components:

- `AppwriteService` - Handles file uploads, downloads, and management with the Appwrite API
- `FilePreviewWidget` - Renders different file types appropriately in the chat
- `MessageBubble` - Displays messages including file attachments
- Enhanced `Message` model to include file metadata

## Project Structure

```
lib/
├── main.dart                  # Entry point
├── models/
│   ├── message.dart           # Message model with file support
│   └── chat_user.dart         # User model
├── screens/
│   ├── chat_screen.dart       # Main chat interface
│   └── ...
├── services/
│   ├── chat_service.dart      # Firebase chat operations
│   ├── appwrite_service.dart  # Appwrite file storage operations
│   └── ...
└── widgets/
    ├── file_preview_widget.dart # Renders different file types
    ├── message_bubble.dart    # Message UI component
    └── ...
```

## Description

Nobblet is a modern chatting application built with Flutter and Firebase, offering a sleek and intuitive messaging experience.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

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
