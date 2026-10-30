// increment_var is what gives each cluster instance its own port, which is what makes
// per-instance probing possible. Note that `pm2 start --env PORT=3200` does NOT do this:
// --env SELECTS an env_<name> block, it does not set a variable.
module.exports = {
  apps: [{
    name: 'healthy-app',
    script: './healthy-app.js',
    instances: 2,
    exec_mode: 'cluster',
    increment_var: 'PORT',
    env: { PORT: 3200 }
  }]
};
