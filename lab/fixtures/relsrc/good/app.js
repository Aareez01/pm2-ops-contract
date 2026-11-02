const http = require('http');
const PORT = parseInt(process.env.PORT || '3600', 10);
const V = process.env.REL_VERSION || 'good';
http.createServer((req, res) => {
  if (req.url === '/health') { res.writeHead(200); return res.end(JSON.stringify({ ok: true, v: V })); }
  res.writeHead(200); res.end(JSON.stringify({ v: V, pid: process.pid }));
}).listen(PORT, '127.0.0.1');
