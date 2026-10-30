const { join } = require('path');
// Evaluated by the pm2 CLI, so the shell's env reaches the app through this block.
module.exports = {
  apps: [{
    name: 'laggy-app',
    script: join(__dirname, 'laggy-app.js'),
    cwd: __dirname,
    instances: 1,
    exec_mode: 'fork',
    env: {
      PORT: 3300,
      LAG_MS: process.env.LAG_MS || '5',
      INSTRUMENTED: process.env.INSTRUMENTED || 'true'
    }
  }]
};
