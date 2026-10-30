// Stands in for Grafana Loki: records every line pushed, so the lab can check for gaps.
const http = require('http');
const fs = require('fs');
const path = require('path');

const OUT = process.env.LOKI_OUT || path.join(__dirname, 'shipped.log');
const PORT = parseInt(process.env.LOKI_PORT || '9100', 10);
// Set to a number to refuse that many pushes, simulating a backend outage.
let refuse = parseInt(process.env.LOKI_REFUSE || '0', 10);

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { if (body.length < 5_000_000) body += c; });
  req.on('end', () => {
    if (req.method !== 'POST') { res.writeHead(404); return res.end(); }
    if (refuse > 0) { refuse--; res.writeHead(503); return res.end('{"error":"down"}'); }
    try {
      const payload = JSON.parse(body);
      const lines = [];
      for (const s of payload.streams ?? []) {
        for (const v of s.values ?? []) lines.push(v[1]);
      }
      if (lines.length) fs.appendFileSync(OUT, lines.join('\n') + '\n');
      console.log(`[loki] accepted ${lines.length} line(s)`);
    } catch (e) {
      console.error('[loki] bad payload:', e.message);
    }
    res.writeHead(204); res.end();
  });
}).listen(PORT, '127.0.0.1', () => console.log(`[loki] listening on ${PORT} -> ${OUT}`));
