DESC="memory-triggered restarts are detected, though PM2 emits nothing on the bus"
run() {
  # max_memory_restart calls reloadProcessId directly; the only trace anywhere is a line
  # in PM2's own daemon log, which is why this detection is opt-in and best-effort.
  pm2x start "$FIXTURES/eco-leaky.config.js" >/dev/null 2>&1
  wait_for 90 "PM2 to trip max_memory_restart" '[ "$(jlist_num leaky-app - pm2_env.restart_time)" -ge 1 ]'

  local restarts; restarts=$(jlist_num leaky-app - pm2_env.restart_time)
  assert_ge "${restarts:-0}" "1" "PM2 restarted the app for exceeding its memory limit"

  wait_for 40 "a memory-restart alert" '[ "$(alerts_count leaky-app memory-restart)" -ge 1 ]'
  local n; n=$(alerts_count leaky-app memory-restart)
  assert_ge "$n" "1" "the memory restart was detected and alerted"
  assert_grep "memoryMb" "$(alerts_raw)" "the alert reports the memory figures"
}
