#!/usr/bin/env bash
# pm2-ops test lab.
#
#   ./lab.sh                 run every scenario
#   ./lab.sh --list          show the scenarios
#   ./lab.sh 10 22           run only scenarios whose filename starts with 10 or 22
#
# Installs both modules the way a user would (pm2 install from a packed tarball),
# then runs scenarios against a live PM2 daemon, resetting app state between each.
#
# PM2_HOME must stay SHORT: PM2 binds $PM2_HOME/rpc.sock and Linux caps unix socket
# paths at 107 chars. Over that the bind fails silently and every pm2 command hangs.
set -u
export LAB="$(cd "$(dirname "$0")" && pwd)"
BASE="$(cd "$LAB/../.." && pwd)"
export FIXTURES="$LAB/fixtures"
export ALERTS_FILE="$LAB/alerts.jsonl"
export PM2_HOME="${PM2_HOME_OVERRIDE:-$HOME/.pm2-lab}"
export PM2_BIN="$BASE/pm2-probe/node_modules/.bin/pm2"
# Memory checks run on the daemon's worker loop; 30s default would make the lab crawl.
export PM2_WORKER_INTERVAL="${PM2_WORKER_INTERVAL:-3000}"

# shellcheck source=lib/common.sh
. "$LAB/lib/common.sh"

if [ "${1:-}" = "--list" ]; then
  for f in "$LAB"/scenarios/*.sh; do
    DESC=""; . "$f"; printf '  %-42s %s\n' "$(basename "$f" .sh)" "$DESC"
  done
  exit 0
fi

SOCK="$PM2_HOME/rpc.sock"
if [ ${#SOCK} -ge 107 ]; then
  echo "FATAL: PM2_HOME too long (${#SOCK} >= 107) - pm2 would hang. Set PM2_HOME_OVERRIDE."
  exit 1
fi
for r in pm2-probe pm2-alertmanager pm2-shipper; do
  [ -f "$BASE/$r/dist/index.js" ] || { echo "FATAL: $r is not built (npm run build)"; exit 1; }
done

cleanup() { pm2x kill >/dev/null 2>&1; }
trap cleanup EXIT

echo "=============================================="
echo " pm2-ops lab"
echo " PM2_HOME=$PM2_HOME  worker=${PM2_WORKER_INTERVAL}ms"
echo "=============================================="

echo
echo "[setup] packing and installing both modules"
rm -f "$LAB"/*.tgz
( cd "$BASE/pm2-probe"        && npm pack --pack-destination "$LAB" >/dev/null 2>&1 )
( cd "$BASE/pm2-alertmanager" && npm pack --pack-destination "$LAB" >/dev/null 2>&1 )
( cd "$BASE/pm2-shipper"       && npm pack --pack-destination "$LAB" >/dev/null 2>&1 )
pm2x kill >/dev/null 2>&1; rm -rf "$PM2_HOME"; mkdir -p "$PM2_HOME"; clear_alerts
pm2x ping >/dev/null 2>&1 || { echo "FATAL: daemon did not start"; exit 1; }

COLLECTOR_OUT="$ALERTS_FILE" pm2x start "$FIXTURES/collector.js" --name collector >/dev/null 2>&1
pm2x install "$LAB"/pm2-probe-*.tgz >/dev/null 2>&1
pm2x install "$LAB"/pm2-alertmanager-*.tgz >/dev/null 2>&1
pm2x install "$LAB"/pm2-shipper-*.tgz >/dev/null 2>&1
# Idle by default: a rotator quietly rotating other scenarios' logs would corrupt them.
pm2x set pm2-shipper:only __none__ >/dev/null 2>&1
pm2x set pm2-alertmanager:configFile "$FIXTURES/alertmanager.yaml" >/dev/null 2>&1
pm2x set pm2-probe:reconcileSeconds 5 >/dev/null 2>&1
sleep 5
for m in pm2-probe pm2-alertmanager pm2-shipper; do
  st=$(jlist_field "$m" - pm2_env.status)
  [ "$st" = "online" ] || { echo "FATAL: $m is '$st', not online"; pm2x logs "$m" --nostream --lines 20; exit 1; }
done
echo "[setup] both modules online as PM2 modules"

TOTAL_PASS=0; TOTAL_FAIL=0; FAILED_SCENARIOS=()
for f in "$LAB"/scenarios/*.sh; do
  name=$(basename "$f" .sh)
  if [ "$#" -gt 0 ]; then
    match=false
    for want in "$@"; do case "$name" in "$want"*) match=true;; esac; done
    [ "$match" = true ] || continue
  fi

  DESC=""; run() { :; }
  # shellcheck disable=SC1090
  . "$f"
  echo
  echo "---- $name"
  echo "     $DESC"
  PASSES=0; FAILURES=0; FAILED_NAMES=()
  reset_apps
  pm2x set pm2-probe:apps '{}' >/dev/null 2>&1
  # Scenarios assert against module logs, so stale lines from the previous scenario
  # would otherwise be matched as if this scenario had produced them.
  pm2x flush >/dev/null 2>&1
  sleep 2
  clear_alerts
  run
  TOTAL_PASS=$((TOTAL_PASS+PASSES)); TOTAL_FAIL=$((TOTAL_FAIL+FAILURES))
  if [ "$FAILURES" -gt 0 ]; then
    FAILED_SCENARIOS+=("$name")
    echo "      --- alerts seen in this scenario ---"
    alerts_dump
  fi
done

echo
echo "=============================================="
echo " assertions: $TOTAL_PASS passed, $TOTAL_FAIL failed"
if [ "$TOTAL_FAIL" -gt 0 ]; then
  echo " failing scenarios: ${FAILED_SCENARIOS[*]}"
  echo "=============================================="
  exit 1
fi
echo " LAB: ALL PASSED"
echo "=============================================="
