# Shared helpers for lab scenarios. Sourced by lab.sh; scenarios use these only.
# shellcheck shell=bash

PASSES=0; FAILURES=0; FAILED_NAMES=()

pass() { PASSES=$((PASSES+1)); echo "      ok   $1"; }
failed() { FAILURES=$((FAILURES+1)); FAILED_NAMES+=("$1"); echo "      FAIL $1"; }

assert()      { if [ "$1" = "true" ] || [ "$1" = "0" ]; then pass "$2"; else failed "$2"; fi; }
assert_eq()   { if [ "$1" = "$2" ]; then pass "$3"; else failed "$3 (got '$1', want '$2')"; fi; }
assert_ne()   { if [ "$1" != "$2" ]; then pass "$3"; else failed "$3 (both '$1')"; fi; }
assert_ge()   { if [ "$1" -ge "$2" ] 2>/dev/null; then pass "$3"; else failed "$3 (got $1, want >= $2)"; fi; }
assert_le()   { if [ "$1" -le "$2" ] 2>/dev/null; then pass "$3"; else failed "$3 (got $1, want <= $2)"; fi; }
assert_grep() { if echo "$2" | grep -qE "$1"; then pass "$3"; else failed "$3 (no match /$1/)"; fi; }
assert_nogrep(){ if echo "$2" | grep -qE "$1"; then failed "$3 (matched /$1/)"; else pass "$3"; fi; }

pm2x() { timeout 60 "$PM2_BIN" "$@"; }

# Poll until a command succeeds, instead of guessing a sleep duration. Fixed sleeps are
# how this lab's first version produced a false failure by checking 3s too early.
wait_for() { # wait_for <seconds> <description> <shell expression>
  local limit="$1" desc="$2"; shift 2
  local expr="$*" waited=0
  # eval in THIS shell so the helpers above are usable inside the condition
  while [ "$waited" -lt "$limit" ]; do
    if eval "$expr" >/dev/null 2>&1; then return 0; fi
    sleep 1; waited=$((waited+1))
  done
  echo "      (timed out after ${limit}s waiting for: $desc)"
  return 1
}

jlist_num() { local v; v=$(jlist_field "$@"); echo "${v:-0}"; }

# pm_ids are assigned across ALL processes, so an app's instances are rarely 0 and 1.
# Hardcoding them is a mistake this lab has now made twice.
instance_ids() {
  pm2x jlist 2>/dev/null | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      console.log(JSON.parse(s).filter(x=>x.name===process.argv[1])
        .map(x=>x.pm_id).sort((a,b)=>a-b).join(" "));});' "$1"
}

jlist_field() { # jlist_field <app> <pm_id|-> <jsonpath-ish field>
  pm2x jlist 2>/dev/null | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const [app,pmid,field]=process.argv.slice(1);
      let rows=JSON.parse(s).filter(x=>x.name===app);
      if(pmid!=="-") rows=rows.filter(x=>String(x.pm_id)===pmid);
      const r=rows[0];
      if(!r){console.log("");return;}
      const v=field.split(".").reduce((o,k)=>o&&o[k],r);
      console.log(v===undefined?"":v);
    });' "$1" "$2" "$3"
}

instance_pids() { # "pm_id=pid,pm_id=pid" sorted
  pm2x jlist 2>/dev/null | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      console.log(JSON.parse(s).filter(x=>x.name===process.argv[1])
        .map(x=>x.pm_id+"="+x.pid).sort().join(","));});' "$1"
}

changed_count() { # changed_count <before> <after>
  node -e '
    const b=process.argv[1].split(",").filter(Boolean), a=process.argv[2].split(",").filter(Boolean);
    const bm=new Map(b.map(x=>x.split("="))), am=new Map(a.map(x=>x.split("=")));
    let n=0; for(const [k,v] of bm) if(am.get(k)!==v) n++; console.log(n);' "$1" "$2"
}

clear_alerts() { : > "$ALERTS_FILE"; }

alerts_count() { # alerts_count <app> [condition] [resolved:true|false|any]
  # NB: `node -e` has no enclosing function, so a top-level `return` is a SyntaxError.
  node -e '
    const fs=require("fs");
    const [f,app,cond,res]=process.argv.slice(1);
    let n=0;
    if(fs.existsSync(f)){
      const rows=fs.readFileSync(f,"utf8").trim().split("\n").filter(Boolean).map(JSON.parse);
      n=rows.filter(r=>{
        const a=r.alert;
        if(app!=="-" && a.app!==app) return false;
        if(cond && cond!=="-" && a.condition!==cond) return false;
        if(res==="true") return a.resolved===true;
        if(res==="false") return a.resolved!==true;
        return true;
      }).length;
    }
    console.log(n);' "$ALERTS_FILE" "$1" "${2:--}" "${3:-false}"
}

alerts_dump() {
  node -e '
    const fs=require("fs");
    const f=process.argv[1];
    const rows = fs.existsSync(f)
      ? fs.readFileSync(f,"utf8").trim().split("\n").filter(Boolean).map(JSON.parse)
      : [];
    if(rows.length===0){ console.log("      (none)"); }
    else for(const r of rows){ const a=r.alert;
      console.log(`      - ${String(a.app).padEnd(16)} ${String(a.condition).padEnd(14)} ${String(a.severity).padEnd(8)} resolved=${a.resolved}`); }
  ' "$ALERTS_FILE"
}

alerts_raw() { cat "$ALERTS_FILE" 2>/dev/null; }

reset_apps() { # remove every non-module app so scenarios cannot contaminate each other
  for app in $(pm2x jlist 2>/dev/null | node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      console.log(JSON.parse(s).filter(x=>!x.pm2_env.pmx_module).map(x=>x.name)
        .filter(n=>n!=="collector").join(" "));});'); do
    pm2x delete "$app" >/dev/null 2>&1
  done
  clear_alerts
}

set_probe_apps() { pm2x set pm2-probe:apps "$1" >/dev/null 2>&1; sleep 2; }
