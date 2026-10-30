DESC="the wire contract crosses from pm2-probe to pm2-alertmanager and on to a webhook"
run() {
  pm2x start "$FIXTURES/eco-healthy.config.js" >/dev/null 2>&1
  wait_for 15 "instances serving" 'curl -sf -m2 http://127.0.0.1:3201/health'
  set_probe_apps '{"healthy-app":{"action":"restart","minHealthy":0,"liveness":{"http":{"path":"/health"},"periodSeconds":2,"timeoutSeconds":1,"failureThreshold":2}}}'
  clear_alerts

  curl -s -m2 http://127.0.0.1:3201/break >/dev/null
  wait_for 40 "the probe-fail alert" '[ "$(alerts_count healthy-app probe-fail)" -ge 1 ]'

  assert_ge "$(alerts_count healthy-app probe-fail)" "1" \
    "pm2-probe emitted, pm2-alertmanager consumed, the collector received"
  local raw; raw=$(alerts_raw)
  assert_grep '"severity":"critical"' "$raw" "a probe trip is critical"
  assert_grep '"condition":"probe-fail"' "$raw" "the condition survived the hop"
  assert_grep '"app":"healthy-app"' "$raw" \
    "the SUBJECT app is named, not the emitting module"

  # Recovery closes the incident rather than leaving it open forever.
  wait_for 60 "the resolution notice" '[ "$(alerts_count healthy-app probe-fail true)" -ge 1 ]'
  assert_ge "$(alerts_count healthy-app probe-fail true)" "1" \
    "a resolution notice followed once the app recovered"
}
