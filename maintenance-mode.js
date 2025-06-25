// Script to enable maintenance mode for Firebase hosting
const fs = require('fs-extra');
const path = require('path');

// Define paths
const BUILD_DIR = path.join(__dirname, 'build', 'web');
const MAINTENANCE_HTML = path.join(__dirname, 'web', 'maintenance.html');

// Create build/web directory if it doesn't exist
console.log('Creating build/web directory if needed...');
fs.ensureDirSync(BUILD_DIR);

// Copy the maintenance.html file to the build directory as index.html
console.log('Copying maintenance.html to build/web/index.html...');
fs.copySync(MAINTENANCE_HTML, path.join(BUILD_DIR, 'index.html'));

// Copy favicon.png to the build directory
console.log('Copying favicon.png to build/web...');
fs.copySync(
  path.join(__dirname, 'web', 'favicon.png'),
  path.join(BUILD_DIR, 'favicon.png')
);

console.log('Maintenance mode files prepared.');
console.log('To deploy maintenance mode, run:');
console.log('firebase deploy --only hosting');
console.log('');
console.log('Or simply use: npm run maintenance:enable');
console.log('');
console.log('After deployment, your site will show the maintenance page.'); 