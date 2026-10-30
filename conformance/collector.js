// Stands in for Slack: records every alert webhook to a JSONL file we can assert on.
const http = require('http');
const fs = require('fs');
const path = require('path');

const OUT = process.env.COLLECTOR_OUT || path.join(__dirname, 'alerts.jsonl');
const PORT = parseInt(process.env.COLLECTOR_PORT || '9099', 10);

http.createServer((req, res) => {
  let body = '';
  req.on('data', (c) => { if (body.length < 200000) body += c; });
  req.on('end', () => {
    if (req.method === 'POST') {
      try {
        const parsed = JSON.parse(body);
        fs.appendFileSync(OUT, JSON.stringify({ at: Date.now(), alert: parsed }) + '\n');
        console.log(`[collector] ${parsed.condition} ${parsed.app} severity=${parsed.severity} resolved=${parsed.resolved}`);
      } catch (e) {
        console.error('[collector] unparseable body:', e.message);
      }
    }
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end('{"ok":true}');
  });
}).listen(PORT, '127.0.0.1', () => console.log(`[collector] listening on ${PORT} -> ${OUT}`));
