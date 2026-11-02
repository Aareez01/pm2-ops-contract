DESC="a good release rolls out instance by instance; a bad one is caught and reverted"
run() {
  local ROOT="$FIXTURES/relroot"
  local CLI="$BASE_DIR/pm2-release/dist/cli/bin.js"
  rm -rf "$ROOT"; mkdir -p "$ROOT/releases/20260101-000000-v1"
  cp "$FIXTURES/relsrc/good/app.js" "$ROOT/releases/20260101-000000-v1/app.js"
  sed -i "s/'good'/'v1'/" "$ROOT/releases/20260101-000000-v1/app.js"
  ln -sfn "$ROOT/releases/20260101-000000-v1" "$ROOT/current"

  cat > "$ROOT/eco.config.js" <<ECO
module.exports = { apps: [{ name: 'relapp', script: '$ROOT/current/app.js',
  cwd: '$ROOT/current', instances: 2, exec_mode: 'cluster',
  increment_var: 'PORT', env: { PORT: 3600 } }] };
ECO
  pm2x start "$ROOT/eco.config.js" >/dev/null 2>&1
  wait_for 25 "both instances serving" \
    'curl -sf -m2 http://127.0.0.1:3600/ && curl -sf -m2 http://127.0.0.1:3601/'
  assert_grep '"v":"v1"' "$(curl -s -m2 http://127.0.0.1:3600/)" "starts on release v1"

  local GATE='--root '"$ROOT"' --keep 3'
  echo "      --- deploy a good release ---"
  local out
  out=$(cd "$ROOT" && PM2_HOME="$PM2_HOME" node "$CLI" deploy relapp --from "$FIXTURES/relsrc/good" $GATE --json 2>/dev/null)
  echo "      $(echo "$out" | head -c 160)"
  assert_grep '"ok":true' "$out" "the deploy reported success"
  local ids; ids=$(instance_ids relapp | tr ' ' ',')
  assert_grep "\"reloaded\":\[$ids\]" "$out" "both instances were rolled, one at a time"
  assert_grep '"v":"good"' "$(curl -s -m2 http://127.0.0.1:3600/)" "instance 0 serves the new release"
  assert_grep '"v":"good"' "$(curl -s -m2 http://127.0.0.1:3601/)" "instance 1 serves the new release"

  echo "      --- deploy a release whose health endpoint fails ---"
  local before_pid
  before_pid=$(curl -s -m2 http://127.0.0.1:3601/ | node -pe 'JSON.parse(require("fs").readFileSync(0,"utf8")).pid')
  out=$(cd "$ROOT" && PM2_HOME="$PM2_HOME" node "$CLI" deploy relapp --from "$FIXTURES/relsrc/bad" $GATE --json 2>/dev/null)
  echo "      $(echo "$out" | head -c 200)"
  assert_grep '"ok":false' "$out" "the bad release was rejected"
  assert_grep '"rolledBack":true' "$out" "it rolled back automatically"
  local first; first=$(instance_ids relapp | awk '{print $1}')
  assert_grep "\"failedAt\":$first" "$out" "it stopped at the FIRST instance, not after breaking both"

  wait_for 30 "the fleet to settle back on the good release" \
    'curl -s -m2 http://127.0.0.1:3600/ | grep -q good'
  assert_grep '"v":"good"' "$(curl -s -m2 http://127.0.0.1:3600/)" "instance 0 is back on the good release"
  assert_grep '"v":"good"' "$(curl -s -m2 http://127.0.0.1:3601/)" "instance 1 is back on the good release"

  echo "      --- release history ---"
  node "$CLI" list relapp --root "$ROOT" 2>/dev/null | sed 's/^/        /'
  local cur; cur=$(readlink "$ROOT/current")
  assert_nogrep "bad" "$cur" "current does not point at the bad release"

  pm2x delete relapp >/dev/null 2>&1
  rm -rf "$ROOT"
}
