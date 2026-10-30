DESC="credentials in stderr are redacted before the alert leaves the host"
run() {
  pm2x start "$FIXTURES/secretive-app.js" --name secretive-app >/dev/null 2>&1
  wait_for 60 "a crash alert carrying the stderr excerpt" '[ "$(alerts_count secretive-app)" -ge 1 ]'
  sleep 3

  local raw; raw=$(alerts_raw)
  assert_ge "$(alerts_count secretive-app)" "1" "the crash was alerted"
  assert_grep "log_excerpt" "$raw" "the alert carried a stderr excerpt"
  assert_grep "ECONNREFUSED" "$raw" "ordinary log content survived"

  # The things that must never reach an external service.
  assert_nogrep "AKIAIOSFODNN7EXAMPLE" "$raw" "the AWS key id was redacted"
  assert_nogrep "hunter2" "$raw" "the database password was redacted"
  assert_grep "redacted" "$raw" "the excerpt is visibly marked as redacted"
}
