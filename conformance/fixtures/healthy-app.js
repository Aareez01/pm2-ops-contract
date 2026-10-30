// Healthy two-instance app whose health can be broken on demand.
const http = require('http');
const PORT = parseInt(process.env.PORT || '3200', 10);
let broken = false;

http.createServer((req, res) => {
  if (req.url === '/break') { broken = true; res.writeHead(200); return res.end('broken\n'); }
  if (req.url === '/health') {
    if (broken) { res.writeHead(503); return res.end('{"ok":false}'); }
    res.writeHead(200); return res.end(JSON.stringify({ ok: true, pid: process.pid, port: PORT }));
  }
  res.writeHead(404); res.end();
}).listen(PORT, '127.0.0.1', () => console.log(`[healthy-app] :${PORT} pid=${process.pid}`));
