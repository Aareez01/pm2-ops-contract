DESC="action:none observes and reports but never restarts (the safe default)"
run() {
  pm2x start "$FIXTURES/eco-healthy.config.js" >/dev/null 2>&1
  wait_for 15 "instances serving" 'curl -sf -m2 http://127.0.0.1:3201/health'
  set_probe_apps '{"healthy-app":{"action":"none","liveness":{"http":{"path":"/health"},"periodSeconds":2,"timeoutSeconds":1,"failureThreshold":2}}}'
  sleep 8

  local before after
  before=$(instance_pids healthy-app)
  curl -s -m2 http://127.0.0.1:3201/break >/dev/null
  sleep 16
  after=$(instance_pids healthy-app)

  assert_eq "$(changed_count "$before" "$after")" "0" "nothing was restarted"
  local n; n=$(alerts_count healthy-app probe-fail)
  assert_ge "$n" "1" "the failure was still detected and reported ($n alert(s))"
  assert_grep "\"probeAction\":\"none\"" "$(alerts_raw)" "the event records that no restart was taken"
}
