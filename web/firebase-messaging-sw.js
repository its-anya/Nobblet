// Give the service worker access to Firebase Messaging.
// Note that you can only use Firebase Messaging here. Other Firebase libraries
// are not available in the service worker.
importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/9.22.1/firebase-messaging-compat.js');

// Initialize the Firebase app in the service worker with your Firebase configuration
firebase.initializeApp({
  apiKey: "AIzaSyDCNmM16TvUZxHLzPrSNEs_uB9YVZT7xFg",
  authDomain: "nobblet.firebaseapp.com",
  projectId: "nobblet",
  storageBucket: "nobblet.firebasestorage.app",
  messagingSenderId: "298332806326",
  appId: "1:298332806326:web:74d7bfe8d9cd009116da17",
  measurementId: "G-WPC3TENB34",
});

// Retrieve an instance of Firebase Messaging so that it can handle background
// messages.
const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('[firebase-messaging-sw.js] Received background message ', payload);
  
  // Customize notification here
  const notificationTitle = payload.notification.title || 'Nobblet';
  const notificationOptions = {
    body: payload.notification.body || 'You have a new message',
    icon: '/favicon.png'
  };

  return self.registration.showNotification(notificationTitle, notificationOptions);
}); 