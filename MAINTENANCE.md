# Maintenance Mode Instructions

This document explains how to enable maintenance mode for your Nobblet Firebase app and how to restore normal operation afterwards.

## Prerequisites

Make sure you have the following installed:
- Node.js
- Flutter SDK
- Firebase CLI (and you're logged in with `firebase login`)

## Enable Maintenance Mode

When you need to temporarily disable your application and show a maintenance page, follow these steps:

1. Make sure you have Node.js installed
2. Run the maintenance mode script:

```bash
npm install
```

3. Deploy the maintenance page to Firebase:

```bash
firebase deploy --only hosting
```

Your application will now display a maintenance page to all users.

## Restore Normal Operation

When you're ready to bring your application back online:

1. Run the restore script:

```bash
node restore-app.js
```

This script will:
- Rebuild your Flutter web application
- Deploy the application to Firebase hosting

Alternatively, you can manually perform these steps:

1. Build your Flutter web application:

```bash
flutter build web
```

2. Deploy to Firebase hosting:

```bash
firebase deploy --only hosting
```

## Customizing the Maintenance Page

If you want to customize the maintenance page:

1. Edit the `web/maintenance.html` file with your desired changes
2. Run the maintenance mode process again to deploy the updated page

## Troubleshooting

If you encounter any issues:

- Make sure you're logged in to Firebase CLI with `firebase login`
- Verify that your Firebase project is correctly set up in `.firebaserc`
- Check that your Flutter environment is working correctly with `flutter doctor`
- Ensure Node.js is installed and functioning with `node --version`

For deployment issues, check the Firebase console for more details about your hosting configuration. 

## Additional Notes

- The maintenance mode process is designed to be run from the root directory of your project
- The maintenance page is served from the `build/web` directory
- The maintenance page is served at the root of your Firebase hosting configuration

## Maintenance Mode Script

The maintenance mode script is a Node.js script that builds your Flutter web application and deploys it to Firebase hosting. It also creates a maintenance page in the `web` directory.

## Restore App Script   

The restore app script is a Node.js script that rebuilds your Flutter web application and deploys it to Firebase hosting.

## Maintenance Page

The maintenance page is a simple HTML file that is served from the `web` directory. It is displayed to all users when maintenance mode is enabled.  

## Maintenance Mode Process

The maintenance mode process is a script that builds your Flutter web application and deploys it to Firebase hosting. It also creates a maintenance page in the `web` directory.

```bash
npm run maintenance:enable
```

```bash
npm run maintenance:disable
```

