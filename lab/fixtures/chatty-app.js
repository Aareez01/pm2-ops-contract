// Writes continuously so a rotation can be observed while writes are in flight.
let n = 0;
setInterval(() => {
  console.log(`[chatty] line ${++n} from pid ${process.pid} ${'x'.repeat(200)}`);
}, 20);
