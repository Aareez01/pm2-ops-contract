// Dies with a non-zero exit code shortly after every start, so PM2 restarts it until it
// hits 'restart overlimit'. This is the crash loop the alertmanager must collapse.
console.error('[crashy-app] starting, will fail shortly');
setTimeout(() => {
  console.error('[crashy-app] fatal: simulated unrecoverable error');
  process.exit(1);
}, 300);
