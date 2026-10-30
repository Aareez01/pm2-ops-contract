const { join } = require('path');
// Cluster mode with 2 instances: each worker owns its own log file descriptor, which
// is the whole point of the experiment. merge_logs stays off, so paths carry -<pm_id>.
module.exports = {
  apps: [{
    name: 'chatty-app',
    script: join(__dirname, 'chatty-app.js'),
    cwd: __dirname,
    instances: 2,
    exec_mode: 'cluster'
  }]
};
