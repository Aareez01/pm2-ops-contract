DESC="renaming a log file does NOT redirect PM2's writes until reloadLogs runs"
run() {
  # The claim under test (F12/F13), on which the whole pm2-shipper rotation design
  # rests. Established by reading PM2's source; never until now by running it.
  pm2x start "$FIXTURES/eco-chatty.config.js" >/dev/null 2>&1
  wait_for 25 "both instances to be online" '[ "$(instance_ids chatty-app | wc -w)" = "2" ]'

  local ID0 ID1 LOG PID0
  read -r ID0 ID1 <<< "$(instance_ids chatty-app)"
  echo "      instances: pm_id $ID0, $ID1"
  wait_for 25 "the app to start logging" \
    '[ -s "$(jlist_field chatty-app "$ID0" pm2_env.pm_out_log_path)" ]'
  LOG=$(jlist_field chatty-app "$ID0" pm2_env.pm_out_log_path)
  PID0=$(jlist_field chatty-app "$ID0" pid)
  echo "      log:  $LOG"
  echo "      pid:  $PID0"
  [ -n "$LOG" ] && [ -f "$LOG" ] || { failed "no log file to test with"; return; }

  grows() { # grows <path> -> 0 if it gained bytes over 2s
    local a b
    a=$(stat -c %s "$1" 2>/dev/null || echo 0); sleep 2
    b=$(stat -c %s "$1" 2>/dev/null || echo 0)
    [ "${b:-0}" -gt "${a:-0}" ]
  }

  echo "      --- step 1: rename the file out from under PM2 ---"
  mv "$LOG" "$LOG.rotated"
  sleep 1

  if grows "$LOG.rotated"; then
    pass "F12 CONFIRMED: workers keep writing to the RENAMED inode"
  else
    failed "F12 WRONG: the renamed file stopped growing"
  fi

  if [ -e "$LOG" ] && grows "$LOG"; then
    failed "F12 WRONG: PM2 recreated and resumed the original path by itself"
  else
    pass "nothing writes to the original path until reloadLogs"
  fi

  # The decisive evidence: the worker process itself holds the descriptor.
  if ls -l "/proc/$PID0/fd" 2>/dev/null | grep -qF "$(basename "$LOG").rotated"; then
    pass "the WORKER process holds the rotated file open (not the daemon)"
  else
    echo "      fds held by $PID0:"
    ls -l "/proc/$PID0/fd" 2>/dev/null | grep -F "$(basename "$LOG" .log)" | sed 's/^/        /'
    failed "the worker does not hold the rotated file - F12's mechanism is different"
  fi

  echo "      --- step 2: tell PM2 to reopen ---"
  pm2x reloadLogs >/dev/null 2>&1
  sleep 2

  if [ -e "$LOG" ] && grows "$LOG"; then
    pass "F13 CONFIRMED: after reloadLogs the workers write to the new file"
  else
    failed "F13 WRONG: the new file is not being written after reloadLogs"
  fi

  if grows "$LOG.rotated"; then
    failed "the rotated file is STILL growing after reloadLogs - disk would keep filling"
  else
    pass "the rotated file stopped growing, so it is safe to compress"
  fi

  echo "      --- step 3: both instances, not just one ---"
  local LOG1; LOG1=$(jlist_field chatty-app "$ID1" pm2_env.pm_out_log_path)
  if [ -n "$LOG1" ] && [ "$LOG1" != "$LOG" ]; then
    pass "instances have separate log paths without merge_logs ($(basename "$LOG1"))"
  else
    failed "expected per-instance log paths, got '$LOG1'"
  fi

  rm -f "$LOG.rotated"
}
