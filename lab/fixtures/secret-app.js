// Reports what it was given, so the lab can see injection and rotation take effect.
const http = require('http');
const PORT = parseInt(process.env.PORT || '3400', 10);
http.createServer((_q, res) => {
  res.writeHead(200, { 'content-type': 'application/json' });
  res.end(JSON.stringify({
    pid: process.pid,
    DB_PASSWORD: process.env.DB_PASSWORD ?? null,
    SECRETS_FILE: process.env.SECRETS_FILE ?? null,
  }));
}).listen(PORT, '127.0.0.1', () =>
  console.log(`[secret-app] :${PORT} pid=${process.pid} DB_PASSWORD=${process.env.DB_PASSWORD ? 'set' : 'unset'}`));
