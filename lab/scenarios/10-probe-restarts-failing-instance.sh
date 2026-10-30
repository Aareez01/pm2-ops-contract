DESC="pm2-liveness restarts only the hung instance, leaving its sibling alone"
run() {
  pm2x start "$FIXTURES/eco-healthy.config.js" >/dev/null 2>&1
  wait_for 15 "both instances serving" 'curl -sf -m2 http://127.0.0.1:3200/health && curl -sf -m2 http://127.0.0.1:3201/health'
  set_probe_apps '{"healthy-app":{"action":"restart","minHealthy":0,"liveness":{"http":{"path":"/health"},"periodSeconds":2,"timeoutSeconds":1,"failureThreshold":2}}}'

  local before after changed
  before=$(instance_pids healthy-app)
  curl -s -m2 http://127.0.0.1:3201/break >/dev/null
  wait_for 40 "the broken instance to be restarted" '[ "$(instance_pids healthy-app)" != "'"$before"'" ]'
  sleep 3
  after=$(instance_pids healthy-app)
  changed=$(changed_count "$before" "$after")
  echo "      pids before: $before"
  echo "      pids after:  $after"

  assert_eq "$changed" "1" "exactly one instance restarted; the healthy sibling untouched"
  curl -sf -m2 http://127.0.0.1:3201/health >/dev/null \
    && pass "the restarted instance serves healthy again" \
    || failed "restarted instance still unhealthy"
}
