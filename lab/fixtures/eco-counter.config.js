const { join } = require('path');
// Single fork instance so the sequence is unambiguous.
module.exports = {
  apps: [{
    name: 'counter-app',
    script: join(__dirname, 'counter-app.js'),
    cwd: __dirname,
    instances: 1,
    exec_mode: 'fork'
  }]
};
