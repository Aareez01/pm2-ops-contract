const http = require('http');
const PORT = parseInt(process.env.PORT || '3600', 10);
http.createServer((req, res) => {
  if (req.url === '/health') { res.writeHead(503); return res.end(JSON.stringify({ ok: false })); }
  res.writeHead(200); res.end(JSON.stringify({ v: 'bad', pid: process.pid }));
}).listen(PORT, '127.0.0.1');
