const { join } = require('path');
// Cluster mode so the zero-downtime reload path is the one exercised.
module.exports = {
  apps: [{
    name: 'secret-app',
    script: join(__dirname, 'secret-app.js'),
    cwd: __dirname,
    instances: 2,
    exec_mode: 'cluster',
    increment_var: 'PORT',
    env: { PORT: 3400 }
  }]
};
