// Script to restore normal operation after maintenance mode
const { execSync } = require('child_process');
const path = require('path');

console.log('Starting restoration of normal application operation...');

try {
  // Run Flutter build web to rebuild the app
  console.log('Building Flutter web application...');
  execSync('flutter build web', { stdio: 'inherit' });
  
  console.log('Build completed successfully.');
  console.log('Deploying normal application to Firebase...');
  
  // Deploy to Firebase
  execSync('firebase deploy --only hosting', { stdio: 'inherit' });
  
  console.log('');
  console.log('✅ Your application has been restored to normal operation!');
  console.log('The maintenance mode has been disabled.');
} catch (error) {
  console.error('Error during restoration:');
  console.error(error.message);
  console.log('');
  console.log('Please try again or manually run:');
  console.log('1. flutter build web');
  console.log('2. firebase deploy --only hosting');
} 