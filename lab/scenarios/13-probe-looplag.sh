DESC="loopLag reads PM2's event-loop metric, and refuses when the metric is absent"
run() {
  # PM2 7 publishes 'Event Loop Latency' (p50) and '... p95' into pm2_env.axm_monitor
  # for every app, with no @pm2/io and no app-side instrumentation. So the only way an
  # app genuinely has no usable metric is a metricName that does not exist.
  echo "      case A: a metricName that does not exist must be refused, not passed"
  pm2x start "$FIXTURES/eco-laggy.config.js" >/dev/null 2>&1
  sleep 3
  set_probe_apps '{"laggy-app":{"action":"none","liveness":{"loopLag":{"maxLagMs":100,"metricName":"No Such Metric"},"periodSeconds":2,"failureThreshold":2}}}'
  wait_for 25 "the guard to refuse the app" 'pm2x logs pm2-probe --nostream --lines 60 2>/dev/null | grep -q "refusing to probe app"'
  local logs; logs=$(pm2x logs pm2-probe --nostream --lines 60 2>/dev/null)
  assert_grep "refusing to probe app" "$logs" "app with no usable metric was refused"
  assert_grep "No Such Metric" "$logs" "the reason names the metric that is missing"
  assert_eq "$(alerts_count laggy-app)" "0" "a refused app produces no false health signal"
  pm2x delete laggy-app >/dev/null 2>&1; clear_alerts

  echo "      case B: PM2's built-in metric is read with no instrumentation at all"
  INSTRUMENTED=false pm2x start "$FIXTURES/eco-laggy.config.js" >/dev/null 2>&1
  sleep 5
  local builtin; builtin=$(jlist_field laggy-app - 'pm2_env.axm_monitor.Event Loop Latency.value')
  assert_ne "$builtin" "" "PM2 publishes Event Loop Latency unprompted (value=$builtin)"
  set_probe_apps '{"laggy-app":{"action":"none","liveness":{"loopLag":{"maxLagMs":1000},"periodSeconds":2,"failureThreshold":2}}}'
  sleep 12
  assert_eq "$(alerts_count laggy-app)" "0" "a healthy loop produces no alert"
  pm2x delete laggy-app >/dev/null 2>&1; clear_alerts

  echo "      case C: an app reporting lag over the threshold must trip"
  LAG_MS=500 pm2x start "$FIXTURES/eco-laggy.config.js" >/dev/null 2>&1
  sleep 5
  set_probe_apps '{"laggy-app":{"action":"none","liveness":{"loopLag":{"maxLagMs":100},"periodSeconds":2,"failureThreshold":2}}}'
  wait_for 40 "a loop-lag alert" '[ "$(alerts_count laggy-app probe-fail)" -ge 1 ]'
  assert_ge "$(alerts_count laggy-app probe-fail)" "1" "lag over the threshold alerted"
  assert_grep '"probe":"loop-lag"' "$(alerts_raw)" "the alert identifies the loop-lag probe"
}
