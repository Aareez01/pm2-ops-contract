DESC="the health gate uses pm2-liveness's verdict, not its own HTTP check"
run() {
  local ROOT="$FIXTURES/relroot61"
  local CLI="$BASE_DIR/pm2-release/dist/cli/bin.js"
  rm -rf "$ROOT"; mkdir -p "$ROOT/releases/20260101-000000-v1"
  cp "$FIXTURES/relsrc/good/app.js" "$ROOT/releases/20260101-000000-v1/app.js"
  ln -sfn "$ROOT/releases/20260101-000000-v1" "$ROOT/current"

  cat > "$ROOT/eco.config.js" <<ECO
module.exports = { apps: [{ name: 'probegate', script: '$ROOT/current/app.js',
  cwd: '$ROOT/current', instances: 2, exec_mode: 'cluster',
  increment_var: 'PORT', env: { PORT: 3620 } }] };
ECO
  pm2x start "$ROOT/eco.config.js" >/dev/null 2>&1
  wait_for 25 "both instances serving" \
    'curl -sf -m2 http://127.0.0.1:3620/health && curl -sf -m2 http://127.0.0.1:3621/health'

  # pm2-liveness probes the app and publishes a verdict per instance. action:none, because
  # this scenario is about the verdict reaching pm2-release, not about restarts.
  set_probe_apps '{"probegate":{"action":"none","minHealthy":0,"liveness":{"http":{"path":"/health"},"periodSeconds":2,"timeoutSeconds":1,"failureThreshold":2}}}'
  assert_grep "probegate" "$(pm2x logs pm2-liveness --nostream --lines 40 2>/dev/null)" \
    "pm2-liveness picked the app up"

  echo "      --- deploy a release whose /health fails ---"
  local out
  out=$(cd "$ROOT" && PM2_HOME="$PM2_HOME" node "$CLI" deploy probegate \
        --from "$FIXTURES/relsrc/bad" --root "$ROOT" --keep 3 --json 2>/dev/null)
  echo "      $(echo "$out" | head -c 220)"

  assert_grep '"ok":false' "$out" "the bad release was rejected"
  # The whole point of the pairing: pm2-liveness decided, not pm2-release's own HTTP check.
  assert_grep 'via probe' "$out" "the verdict came from pm2-liveness, not the fallback"
  assert_grep '"rolledBack":true' "$out" "it rolled back"

  wait_for 30 "the fleet to settle back on the good release" \
    'curl -s -m2 http://127.0.0.1:3620/health | grep -q "\"ok\":true"'
  assert_grep '"ok":true' "$(curl -s -m2 http://127.0.0.1:3620/health)" "instance is healthy again"

  local cur; cur=$(readlink "$ROOT/current")
  assert_grep "20260101-000000-v1" "$cur" "current is back on the release that works"

  pm2x delete probegate >/dev/null 2>&1
  rm -rf "$ROOT"
}
