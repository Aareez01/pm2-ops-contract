DESC="a crash-looping app produces a bounded number of alerts, not one per restart"
run() {
  pm2x start "$FIXTURES/crashy-app.js" --name crashy-app >/dev/null 2>&1
  wait_for 60 "PM2 to rack up restarts" '[ "$(jlist_num crashy-app - pm2_env.restart_time)" -ge 8 ]'
  sleep 6

  local restarts alerts
  restarts=$(jlist_num crashy-app - pm2_env.restart_time)
  alerts=$(alerts_count crashy-app)
  echo "      actual restarts: $restarts   alerts sent: $alerts"

  assert_ge "$alerts" "1" "the crash loop was reported at all"
  assert_le "$alerts" "4" "alert count is bounded"
  if [ "$restarts" -gt 0 ] && [ "$alerts" -lt "$restarts" ]; then
    pass "alerts ($alerts) << restarts ($restarts): collapse works under real load"
  else
    failed "alerts did not collapse relative to restarts"
  fi
  assert_ge "$(alerts_count crashy-app crash-loop)" "1" "the loop itself was escalated to critical"
}
