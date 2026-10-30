// Publishes an axm:monitor metric exactly as an instrumented app does. PM2's daemon
// merges msg.data into pm2_env.axm_monitor, which is where pm2-probe reads loopLag from.
// LAG_MS controls the reported figure; INSTRUMENTED=false publishes nothing at all,
// so the "uninstrumented app is refused, not silently passed" case can be exercised.
const http = require('http');
const LAG = parseFloat(process.env.LAG_MS || '5');
const INSTRUMENTED = process.env.INSTRUMENTED !== 'false';
const PORT = parseInt(process.env.PORT || '3300', 10);

if (INSTRUMENTED) {
  setInterval(() => {
    if (process.send) {
      process.send({ type: 'axm:monitor', data: { 'Event Loop Latency': { value: LAG, unit: 'ms' } } });
    }
  }, 1000).unref?.();
}

http.createServer((_req, res) => { res.writeHead(200); res.end('ok'); })
  .listen(PORT, '127.0.0.1', () => console.log(`[laggy-app] :${PORT} lag=${LAG} instrumented=${INSTRUMENTED}`));
setInterval(() => {}, 1 << 30);
