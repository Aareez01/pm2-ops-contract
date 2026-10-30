// Allocates steadily so PM2's max_memory_restart trips. The restart it causes emits
// NOTHING on the bus - the only trace is a line in PM2's own daemon log.
const hold = [];
console.log('[leaky-app] allocating');
setInterval(() => {
  hold.push(Buffer.alloc(8 * 1024 * 1024, 1));   // 8MB a tick
  if (hold.length % 5 === 0) console.log(`[leaky-app] ${hold.length * 8}MB held`);
}, 300);
