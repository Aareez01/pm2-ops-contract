// Emits a strictly increasing sequence so the collector can prove there are no GAPS.
// Duplicates are expected and fine; a missing number is data loss.
let n = 0;
setInterval(() => { console.log(`SEQ ${++n}`); }, 25);
