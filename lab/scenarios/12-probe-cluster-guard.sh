DESC="a cluster app whose instances share a port is refused, not probed blindly"
run() {
  # No increment_var: both instances behind one port, so PM2 routes to an arbitrary
  # worker and per-instance probing is impossible.
  pm2x start "$FIXTURES/healthy-app.js" --name healthy-app -i 2 >/dev/null 2>&1
  sleep 4
  set_probe_apps '{"healthy-app":{"action":"restart","liveness":{"http":{"path":"/health","port":3200},"periodSeconds":2,"failureThreshold":2}}}'
  sleep 10

  local logs; logs=$(pm2x logs pm2-probe --nostream --lines 60 2>/dev/null)
  assert_grep "refusing to probe app" "$logs" "the app was refused rather than probed"
  assert_grep "fixed port|share|no resolvable PORT" "$logs" "the reason explains why"
  assert_grep "increment_var" "$logs" "the log names a concrete remedy"

  local before after
  before=$(instance_pids healthy-app); sleep 8; after=$(instance_pids healthy-app)
  assert_eq "$(changed_count "$before" "$after")" "0" "no instance was restarted on a guess"
}
