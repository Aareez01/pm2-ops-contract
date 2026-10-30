DESC="secrets are injected into a running app, and a rotation is applied zero-downtime"
run() {
  local SECFILE="$FIXTURES/secrets.json"
  local SECCFG="$FIXTURES/secrets-config.yaml"
  local SECDIR="$FIXTURES/secret-store"
  rm -rf "$SECDIR"; mkdir -p "$SECDIR"

  printf '{"prod/db":"first-value-111"}\n' > "$SECFILE"; chmod 600 "$SECFILE"
  cat > "$SECCFG" <<YAML
logLevel: debug
refreshSeconds: 3
secretsDir: $SECDIR
backends:
  vault: { type: file, path: $SECFILE }
apps:
  secret-app:
    secrets: { DB_PASSWORD: prod/db }
    mode: env
YAML

  pm2x start "$FIXTURES/eco-secret.config.js" >/dev/null 2>&1
  wait_for 25 "the app to serve" 'curl -sf -m2 http://127.0.0.1:3400/'
  local before; before=$(curl -s -m2 http://127.0.0.1:3400/)
  echo "      before: $before"
  assert_grep '"DB_PASSWORD":null' "$before" "the app starts with no secret"

  pm2x set pm2-secrets:configFile "$SECCFG" >/dev/null 2>&1

  wait_for 45 "the secret to be injected" \
    'curl -s -m2 http://127.0.0.1:3400/ | grep -q first-value-111'
  local after; after=$(curl -s -m2 http://127.0.0.1:3400/)
  assert_grep 'first-value-111' "$after" "the secret reached the running app"

  echo "      --- rotate the secret ---"
  printf '{"prod/db":"rotated-value-222"}\n' > "$SECFILE"; chmod 600 "$SECFILE"
  wait_for 45 "the rotation to be applied" \
    'curl -s -m2 http://127.0.0.1:3400/ | grep -q rotated-value-222'
  assert_grep 'rotated-value-222' "$(curl -s -m2 http://127.0.0.1:3400/)" \
    "the rotated value replaced the old one"

  local logs; logs=$(pm2x logs pm2-secrets --nostream --lines 60 2>/dev/null)
  assert_grep 'reload \(zero downtime\)' "$logs" "a cluster app was reloaded, not restarted"
  assert_nogrep 'rotated-value-222' "$logs" "the module never logged the secret value"

  echo "      --- file mode keeps values out of pm2_env ---"
  sed -i 's/    mode: env/    mode: file/' "$SECCFG"
  printf '{"prod/db":"file-mode-333"}\n' > "$SECFILE"; chmod 600 "$SECFILE"
  # NB: grep -q SECRETS_FILE would match the JSON KEY, which is always present even
  # when the value is null - it would pass instantly and test nothing.
  wait_for 60 "file mode to take effect" \
    'curl -s -m2 http://127.0.0.1:3400/ | grep -q "secret-app.json"'
  local fm; fm=$(curl -s -m2 http://127.0.0.1:3400/)
  assert_grep 'secret-app.json' "$fm" "the app received a path, not the value"
  assert_nogrep 'file-mode-333' "$fm" "the value itself is not in the app env"

  local perms; perms=$(stat -c '%a' "$SECDIR/secret-app.json" 2>/dev/null)
  assert_eq "$perms" "600" "the secrets file is owner-only"
  assert_nogrep 'file-mode-333' "$(pm2x jlist 2>/dev/null)" \
    "the value never entered pm2_env where pm2 jlist would expose it"

  pm2x set pm2-secrets:configFile "" >/dev/null 2>&1
  rm -rf "$SECDIR" "$SECFILE" "$SECCFG"
}
