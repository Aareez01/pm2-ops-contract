#!/usr/bin/env bash
# Suite-level conformance test for pm2-probe + pm2-alertmanager.
#
# This exercises the two paths that unit tests and per-module integration tests cannot:
#   1. The REAL `pm2 install` path - pmx_module, module_conf.json, pm2 set restarts.
#   2. The wire contract ACROSS process boundaries - pm2-probe emits, pm2-alertmanager
#      consumes, a webhook collector records what a human would have been sent.
#
# PM2_HOME must stay short: PM2 binds $PM2_HOME/rpc.sock and Linux caps unix socket
# paths at 107 chars. Over that, the bind fails silently and every pm2 command hangs.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$HERE/../.." && pwd)"
FIX="$HERE/fixtures"
PROBE_REPO="$BASE/pm2-probe"
ALERT_REPO="$BASE/pm2-alertmanager"
ALERTS="$HERE/alerts.jsonl"

export PM2_HOME="${PM2_HOME_OVERRIDE:-$HOME/.pm2-conf}"
PM2="$PROBE_REPO/node_modules/.bin/pm2"
P() { timeout 120 "$PM2" "$@"; }

FAILED=0
ok()   { echo "  PASS  $1"; }
fail() { echo "  FAIL  $1"; FAILED=1; }
hr()   { echo; echo "========== $1 =========="; }

count_alerts() {  # count_alerts <app> [condition]
  node -e '
    const fs=require("fs");
    const [file,app,cond]=process.argv.slice(1);
    if(!fs.existsSync(file)){console.log(0);process.exit(0);}
    const rows=fs.readFileSync(file,"utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
    console.log(rows.filter(r=>r.alert.app===app&&(!cond||r.alert.condition===cond)&&!r.alert.resolved).length);
  ' "$ALERTS" "$1" "${2:-}"
}

hr "0. preflight"
SOCK="$PM2_HOME/rpc.sock"
echo "PM2_HOME = $PM2_HOME  (socket path ${#SOCK} chars, limit 107)"
[ ${#SOCK} -lt 107 ] || { echo "FATAL: PM2_HOME too long"; exit 1; }
for r in "$PROBE_REPO" "$ALERT_REPO"; do
  [ -f "$r/dist/index.js" ] || { echo "FATAL: $r/dist missing - run npm run build there"; exit 1; }
done

cleanup() { P kill >/dev/null 2>&1; }
trap cleanup EXIT

hr "1. pack both modules (pm2 install resolves a .tgz to its canonic module name)"
rm -f "$HERE"/*.tgz
( cd "$PROBE_REPO" && npm pack --pack-destination "$HERE" >/dev/null 2>&1 )
( cd "$ALERT_REPO" && npm pack --pack-destination "$HERE" >/dev/null 2>&1 )
PROBE_TGZ=$(ls "$HERE"/pm2-probe-*.tgz 2>/dev/null | head -1)
ALERT_TGZ=$(ls "$HERE"/pm2-alertmanager-*.tgz 2>/dev/null | head -1)
echo "  $(basename "$PROBE_TGZ")"; echo "  $(basename "$ALERT_TGZ")"

hr "2. clean daemon"
P kill >/dev/null 2>&1; rm -rf "$PM2_HOME"; rm -f "$ALERTS"; mkdir -p "$PM2_HOME"
P ping >/dev/null 2>&1 || { echo "FATAL: daemon did not start"; exit 1; }

hr "3. start the alert collector"
COLLECTOR_OUT="$ALERTS" P start "$HERE/collector.js" --name collector >/dev/null 2>&1
sleep 2
curl -s -m 2 -X POST -d '{"app":"selftest","condition":"selftest"}' \
  -H 'content-type: application/json' http://127.0.0.1:9099/alert >/dev/null \
  && ok "collector is accepting webhooks" || fail "collector not reachable"
rm -f "$ALERTS"

hr "4. pm2 install both modules (the real install path)"
P install "$PROBE_TGZ" 2>&1 | tail -3
P install "$ALERT_TGZ" 2>&1 | tail -3
sleep 3
P list 2>&1 | grep -E "pm2-probe|pm2-alertmanager" >/dev/null \
  && ok "both modules installed and running" || fail "modules are not running"

hr "5. configure via pm2 set (this also restarts each module)"
P set pm2-alertmanager:configFile "$FIX/alertmanager.yaml" >/dev/null 2>&1
P set pm2-probe:reconcileSeconds 5 >/dev/null 2>&1
P set pm2-probe:apps '{"healthy-app":{"action":"restart","minHealthy":0,"liveness":{"http":{"path":"/health"},"periodSeconds":2,"timeoutSeconds":1,"failureThreshold":2}}}' >/dev/null 2>&1
sleep 4
P jlist 2>/dev/null | node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    const l=JSON.parse(s);
    for (const n of ["pm2-probe","pm2-alertmanager"]) {
      const p=l.find(x=>x.name===n);
      console.log(`  ${n}: status=${p?p.pm2_env.status:"MISSING"} pmx_module=${p?p.pm2_env.pmx_module:"-"} restarts=${p?p.pm2_env.restart_time:"-"}`);
    }
  });'

hr "6. start the healthy app (2 cluster instances, distinct ports)"
cd "$FIX" || exit 1
P start "$FIX/healthy-ecosystem.config.js" >/dev/null 2>&1
sleep 6
curl -s -m 2 http://127.0.0.1:3200/health >/dev/null && ok "instance 0 serving on :3200" \
  || fail "instance 0 not serving"
curl -s -m 2 http://127.0.0.1:3201/health >/dev/null && ok "instance 1 serving on :3201" \
  || fail "instance 1 not serving (increment_var did not give distinct ports)"

hr "7. PHASE A - probe detects, alertmanager reports (the contract, end to end)"
echo "  breaking instance 1 (:3201) only ..."
snapshot() { P jlist 2>/dev/null | node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{console.log(JSON.parse(s).filter(x=>x.name==="healthy-app").map(x=>x.pm_id+"="+x.pid).sort().join(","))})'; }
BEFORE=$(snapshot)
curl -s -m 2 http://127.0.0.1:3201/break >/dev/null
sleep 30
AFTER=$(snapshot)
echo "  before: $BEFORE"
echo "  after:  $AFTER"
CHANGED=$(node -e '
  const b=process.argv[1].split(",").filter(Boolean), a=process.argv[2].split(",").filter(Boolean);
  const bm=new Map(b.map(x=>x.split("="))), am=new Map(a.map(x=>x.split("=")));
  let n=0; for (const [k,v] of bm) if (am.get(k)!==v) n++;
  console.log(n);' "$BEFORE" "$AFTER")
[ "$CHANGED" = "1" ] \
  && ok "exactly one instance was restarted - the healthy sibling was left alone" \
  || fail "$CHANGED instances changed pid, expected exactly 1"
PROBE_ALERTS=$(count_alerts healthy-app probe-fail)
echo "  probe-fail alerts received by collector: $PROBE_ALERTS"
[ "$PROBE_ALERTS" -ge 1 ] \
  && ok "pm2-probe event crossed to pm2-alertmanager and reached the collector" \
  || fail "no probe-fail alert arrived - the wire contract did not work end to end"

hr "8. PHASE B - crash loop is collapsed, not forwarded"
P start "$FIX/crashy-app.js" --name crashy-app >/dev/null 2>&1
sleep 45
RESTARTS=$(P jlist 2>/dev/null | node -e '
  let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
    const p=JSON.parse(s).find(x=>x.name==="crashy-app");
    console.log(p?p.pm2_env.restart_time:0);});')
CRASH_ALERTS=$(count_alerts crashy-app)
echo "  crashy-app actual restarts: $RESTARTS"
echo "  alerts sent for crashy-app: $CRASH_ALERTS"

[ "$CRASH_ALERTS" -ge 1 ] && ok "the crash loop was reported at all" \
  || fail "crash loop produced no alert"
[ "$CRASH_ALERTS" -le 4 ] && ok "alert count is bounded (<=4), not one per restart" \
  || fail "alert count $CRASH_ALERTS is not bounded"
if [ "$RESTARTS" -gt 0 ] && [ "$CRASH_ALERTS" -lt "$RESTARTS" ]; then
  ok "alerts ($CRASH_ALERTS) << restarts ($RESTARTS) - collapse works under real load"
else
  fail "alerts did not collapse relative to restarts"
fi

hr "9. what the collector actually received"
if [ -f "$ALERTS" ]; then
  node -e '
    const fs=require("fs");
    const rows=fs.readFileSync(process.argv[1],"utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
    for (const r of rows) {
      const a=r.alert;
      console.log(`  ${new Date(r.at).toISOString().slice(11,19)}  ${a.app.padEnd(12)} ${String(a.condition).padEnd(12)} ${String(a.severity).padEnd(8)} resolved=${a.resolved} pm_ids=${JSON.stringify(a.pm_ids)}`);
    }
    console.log(`  (${rows.length} total)`);
  ' "$ALERTS"
else
  echo "  (no alerts file)"
fi

hr "10. module logs"
echo "--- pm2-probe ---";        P logs pm2-probe --nostream --lines 8 2>/dev/null | grep -v '^$' | tail -6
echo "--- pm2-alertmanager ---"; P logs pm2-alertmanager --nostream --lines 12 2>/dev/null | grep -v '^$' | tail -10

hr "result"
[ "$FAILED" -eq 0 ] && echo "CONFORMANCE: ALL PASSED" || echo "CONFORMANCE: FAILURES"
exit $FAILED
