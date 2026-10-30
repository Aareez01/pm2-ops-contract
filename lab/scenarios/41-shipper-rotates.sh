DESC="pm2-shipper rotates a live cluster app, compresses, and holds a disk cap"
run() {
  pm2x start "$FIXTURES/eco-chatty.config.js" >/dev/null 2>&1
  wait_for 25 "both instances online" '[ "$(instance_ids chatty-app | wc -w)" = "2" ]'
  local ID0 ID1 LOG DIR
  read -r ID0 ID1 <<< "$(instance_ids chatty-app)"
  wait_for 25 "the app to start logging" \
    '[ -s "$(jlist_field chatty-app "$ID0" pm2_env.pm_out_log_path)" ]'
  LOG=$(jlist_field chatty-app "$ID0" pm2_env.pm_out_log_path)
  DIR=$(dirname "$LOG")
  echo "      watching $LOG"

  # Small threshold and a tight cap so several rotations happen inside the scenario.
  pm2x set pm2-shipper:maxSize 64K       >/dev/null 2>&1
  pm2x set pm2-shipper:maxTotalSize 10M  >/dev/null 2>&1
  pm2x set pm2-shipper:maxArchives 2     >/dev/null 2>&1
  pm2x set pm2-shipper:checkSeconds 3    >/dev/null 2>&1
  pm2x set pm2-shipper:only chatty-app   >/dev/null 2>&1

  archives() { ls -1 "$DIR"/"$(basename "$LOG")".* 2>/dev/null | wc -l; }
  gzips()    { ls -1 "$DIR"/"$(basename "$LOG")".*.gz 2>/dev/null | wc -l; }

  wait_for 60 "the first rotation" '[ "$(gzips)" -ge 1 ]'
  assert_ge "$(gzips)" "1" "a compressed archive was produced"

  # The live file must be back under the threshold: it was genuinely rotated, not copied.
  local live; live=$(stat -c %s "$LOG" 2>/dev/null || echo 999999999)
  echo "      live log size after rotation: $live bytes (threshold 65536)"
  [ "$live" -lt 200000 ] && pass "the live log was truncated by the rotation" \
    || failed "the live log is still $live bytes"

  # F12 in anger: if PM2 had not reopened, the app would still be writing to the archive.
  local arch a1 a2
  arch=$(ls -1t "$DIR"/"$(basename "$LOG")".*.gz 2>/dev/null | head -1)
  a1=$(stat -c %s "$arch" 2>/dev/null || echo 0); sleep 3
  a2=$(stat -c %s "$arch" 2>/dev/null || echo 0)
  assert_eq "$a1" "$a2" "the archive is not still growing (workers reopened)"

  # And the app is still logging - into the new file. A rotation can land between the
  # two samples and shrink the file, so a fresh archive counts as progress too.
  local s1 s2 g1 g2
  s1=$(stat -c %s "$LOG"); g1=$(gzips); sleep 4
  s2=$(stat -c %s "$LOG"); g2=$(gzips)
  if [ "$s2" -gt "$s1" ] || [ "$g2" -gt "$g1" ]; then
    pass "the app keeps logging into the new file"
  else
    failed "nothing is being written after rotation (size $s1 -> $s2, archives $g1 -> $g2)"
  fi

  echo "      --- retention: maxArchives=2 ---"
  wait_for 90 "several rotations" '[ "$(gzips)" -ge 2 ]'
  sleep 10
  local n; n=$(archives)
  echo "      archives on disk: $n"
  assert_le "$n" "3" "old archives are deleted to honour the cap"

  pm2x set pm2-shipper:only __none__ >/dev/null 2>&1
}
