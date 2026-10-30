const { join } = require('path');
module.exports = {
  apps: [{
    name: 'leaky-app',
    script: join(__dirname, 'leaky-app.js'),
    cwd: __dirname,
    instances: 1,
    exec_mode: 'fork',
    max_memory_restart: '80M'
  }]
};
