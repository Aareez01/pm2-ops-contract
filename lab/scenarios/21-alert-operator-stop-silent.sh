DESC="an operator stopping an app is not an incident, but a probe restart still is"
run() {
  pm2x start "$FIXTURES/eco-healthy.config.js" >/dev/null 2>&1
  wait_for 15 "instances serving" 'curl -sf -m2 http://127.0.0.1:3200/health'
  sleep 8   # clear the startup grace window
  clear_alerts

  pm2x stop healthy-app >/dev/null 2>&1
  sleep 20
  local n; n=$(alerts_count healthy-app)
  assert_eq "$n" "0" "a deliberate pm2 stop produced no alert"

  # The same events carry manually=true when pm2-liveness restarts something, which is why
  # that flag must never be used to decide what is operator action.
  pm2x delete healthy-app >/dev/null 2>&1
  clear_alerts
  pm2x start "$FIXTURES/eco-healthy.config.js" >/dev/null 2>&1
  wait_for 15 "instances serving" 'curl -sf -m2 http://127.0.0.1:3201/health'
  set_probe_apps '{"healthy-app":{"action":"restart","minHealthy":0,"liveness":{"http":{"path":"/health"},"periodSeconds":2,"timeoutSeconds":1,"failureThreshold":2}}}'
  curl -s -m2 http://127.0.0.1:3201/break >/dev/null
  wait_for 40 "a probe-fail alert" '[ "$(alerts_count healthy-app probe-fail)" -ge 1 ]'
  assert_ge "$(alerts_count healthy-app probe-fail)" "1" \
    "a probe-initiated restart DID alert despite manually=true"
}
