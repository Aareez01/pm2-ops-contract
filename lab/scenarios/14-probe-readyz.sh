DESC="/livez and /readyz report degraded state to a load balancer"
run() {
  pm2x set pm2-probe:endpointEnabled true >/dev/null 2>&1
  pm2x set pm2-probe:endpointPort 9615 >/dev/null 2>&1
  pm2x start "$FIXTURES/eco-healthy.config.js" >/dev/null 2>&1
  wait_for 15 "instances serving" 'curl -sf -m2 http://127.0.0.1:3201/health'
  set_probe_apps '{"healthy-app":{"action":"none","liveness":{"http":{"path":"/health"},"periodSeconds":2,"timeoutSeconds":1,"failureThreshold":2}}}'
  wait_for 25 "the endpoint to come up" 'curl -sf -m2 http://127.0.0.1:9615/livez'

  local code
  code=$(curl -s -o /dev/null -w '%{http_code}' -m2 http://127.0.0.1:9615/livez)
  assert_eq "$code" "200" "/livez is 200 while healthy"

  curl -s -m2 http://127.0.0.1:3200/break >/dev/null
  curl -s -m2 http://127.0.0.1:3201/break >/dev/null
  sleep 14
  code=$(curl -s -o /dev/null -w '%{http_code}' -m2 http://127.0.0.1:9615/livez)
  assert_eq "$code" "503" "/livez is 503 once every instance is unhealthy"
  local body; body=$(curl -s -m2 http://127.0.0.1:9615/livez)
  assert_grep '"healthy-app":false' "$body" "the body names the failing app"
  code=$(curl -s -o /dev/null -w '%{http_code}' -m2 http://127.0.0.1:9615/nope)
  assert_eq "$code" "404" "unknown paths 404"
  pm2x set pm2-probe:endpointEnabled false >/dev/null 2>&1
}
