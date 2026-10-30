const { join } = require('path');
module.exports = {
  apps: [{
    name: 'healthy-app',
    script: join(__dirname, 'healthy-app.js'),
    cwd: __dirname,
    instances: 2,
    exec_mode: 'cluster',
    increment_var: 'PORT',   // what gives each instance its own port
    env: { PORT: 3200 }
  }]
};
