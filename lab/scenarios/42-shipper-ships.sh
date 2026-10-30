DESC="logs reach the backend, and a restart mid-stream loses nothing"
run() {
  local SHIPPED="$FIXTURES/shipped.log"
  rm -f "$SHIPPED"
  LOKI_OUT="$SHIPPED" pm2x start "$FIXTURES/loki-collector.js" --name loki >/dev/null 2>&1
  wait_for 15 "the collector to listen" 'curl -s -m2 -X POST -d "{}" http://127.0.0.1:9100/loki/api/v1/push'

  pm2x start "$FIXTURES/eco-counter.config.js" >/dev/null 2>&1
  wait_for 20 "the app to start logging" \
    '[ -s "$(jlist_field counter-app - pm2_env.pm_out_log_path)" ]'

  pm2x set pm2-shipper:maxSize 50M                        >/dev/null 2>&1
  pm2x set pm2-shipper:only counter-app                   >/dev/null 2>&1
  pm2x set pm2-shipper:shipUrl http://127.0.0.1:9100      >/dev/null 2>&1
  pm2x set pm2-shipper:shipPollSeconds 1                  >/dev/null 2>&1
  pm2x set pm2-shipper:shipEnabled true                   >/dev/null 2>&1

  # Reports: <count> <min> <max> <distinct> <gaps>
  seqstats() {
    node -e '
      const fs=require("fs"), f=process.argv[1];
      if(!fs.existsSync(f)){console.log("0 0 0 0 0");process.exit(0);}
      const ns=fs.readFileSync(f,"utf8").split("\n")
        .map(l=>/SEQ (\d+)/.exec(l)).filter(Boolean).map(m=>Number(m[1]));
      if(!ns.length){console.log("0 0 0 0 0");process.exit(0);}
      const set=new Set(ns), min=Math.min(...ns), max=Math.max(...ns);
      let gaps=0; for(let i=min;i<=max;i++) if(!set.has(i)) gaps++;
      console.log(`${ns.length} ${min} ${max} ${set.size} ${gaps}`);
    ' "$SHIPPED"
  }

  wait_for 60 "the first lines to arrive" '[ "$(seqstats | cut -d" " -f1)" -gt 5 ]'
  read -r total min max distinct gaps <<< "$(seqstats)"
  echo "      received $total line(s), SEQ $min..$max, $distinct distinct, $gaps gap(s)"
  assert_ge "$total" "5" "lines reached the backend"
  assert_eq "$gaps" "0" "no gaps in the delivered sequence"

  echo "      --- restart the shipper mid-stream ---"
  pm2x restart pm2-shipper >/dev/null 2>&1
  sleep 12
  read -r total min max distinct gaps <<< "$(seqstats)"
  echo "      after restart: $total line(s), SEQ $min..$max, $distinct distinct, $gaps gap(s)"
  assert_eq "$gaps" "0" "a restart mid-stream produced no gap"
  assert_ge "$max" "$((min + 10))" "shipping resumed and kept up"

  echo "      --- backend refuses for a while ---"
  local before_max="$max"
  pm2x stop loki >/dev/null 2>&1
  sleep 8
  LOKI_OUT="$SHIPPED" pm2x restart loki >/dev/null 2>&1
  wait_for 60 "shipping to catch up after the outage" \
    '[ "$(seqstats | cut -d" " -f3)" -gt '"$before_max"' ]'
  read -r total min max distinct gaps <<< "$(seqstats)"
  echo "      after outage: $total line(s), SEQ $min..$max, $distinct distinct, $gaps gap(s)"
  assert_eq "$gaps" "0" "nothing was lost while the backend was unreachable"

  pm2x set pm2-shipper:shipEnabled false >/dev/null 2>&1
  pm2x set pm2-shipper:only __none__     >/dev/null 2>&1
  pm2x delete loki >/dev/null 2>&1
  rm -f "$SHIPPED"
}
