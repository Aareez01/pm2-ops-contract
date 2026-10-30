# Platform Constraints & Shared Event Contract

**Status:** Draft · **Date:** 2026-10-30 · **Verified against:** PM2 7.1.1 (source inspection + executed tests)

Scope decision: Phase 1 is `pm2-probe` and `pm2-alertmanager` only. Open-source, published to npm,
installed via `pm2 install`. TypeScript, **independent repositories**.

Because the repos are independent, the link between them must be a **versioned wire contract**, not a
shared TypeScript type. This document is that contract, plus the platform facts both modules depend on.

---

## 1. Verified platform findings

These were established by reading and executing PM2 7.1.1 locally, not from documentation. Each one
changes a requirement, so they are recorded with their evidence.

### F1 — Custom keys in `ecosystem.config.js` are silently discarded

`Common.verifyConfs()` passes every app through `Config.validateJSON()`
(`lib/tools/Config.js`), which builds its result as a **whitelist**: it iterates the 65 keys in
`lib/API/schema.json`, copies matching keys into a fresh object, and returns that. Unknown keys are
never copied. The only escape hatch is one regex key, `^env_\S*$`.

Executed test result:

| Key in ecosystem config | Survives into `pm2_env`? |
|---|---|
| `probe: { ... }` | **No** |
| `pm2_ops: { probe: ... }` | **No** |
| `env_probe: { ... }` | Yes (matches the regex) |
| `name`, `script`, `env` | Yes |

**Consequence:** the gap-analysis document proposes "a `probe` block in `ecosystem.config.js`". That
mechanism does not work and must not be specified. No warning is printed — the key vanishes silently,
which would be a miserable first-run experience.

**Re-confirmed against a live daemon.** The walking skeleton started a real app from an ecosystem file
containing both `probe` and `pm2_ops` keys; `pm2 jlist` reported `probe: false`, `pm2_ops: false`.

### F2 — Three config channels actually exist

| Channel | Mechanism | Survives? | Visible to module via |
|---|---|---|---|
| **Module config** | `pm2 set <module>:<key> <value>` → `~/.pm2/module_conf.json` | Yes | module's own env at boot |
| **App env vars** | `env: { PM2_PROBE_HTTP: '...' }` | Yes | `pm2.list()` → `pm2_env` |
| **Sidecar file** | module reads its own file (e.g. `pm2-probe.config.js`) | Yes | direct file read |

`env_*` is technically available but is PM2's deploy-environment mechanism (`--env <name>`);
hijacking it would collide with legitimate use. **Do not use it.**

**Live-verified:** app env vars are readable from `pm2.list()` at **both** `pm2_env.PORT` and
`pm2_env.env.PORT`. Consumers should check both, since which one is populated depends on how the app
was started. `increment_var: 'PORT'` correctly yielded distinct ports per instance
(`pm_id0=:3100, pm_id1=:3101`), which is what makes per-instance HTTP probing possible at all — see
REQ-PR-11 and the cluster-mode caveat in `pm2-probe/docs/requirements.md`.

### F3 — `pm2 set` *does* restart the target module

`CLI.prototype.set` calls `that.restart(app_name, { updateEnv: true })` when the key contains `:` or
`.`. So config changes applied through `pm2 set` take effect automatically.

Hand-editing `module_conf.json` via `pm2 conf` does **not** — PM2 prints "To take changes into
account, please restart module related." Both modules must therefore tolerate a restart as the normal
config-reload path, and must not assume in-process hot reload.

### F4 — The native event vocabulary (corrected by live run)

`God.notify()` is called with these action names (`lib/God.js`, `lib/God/ActionMethods.js`):

- `start`
- `online`
- `exit`
- `restart overlimit` — note the **space**, not a colon or underscore

**A `restart` event also exists.** It is emitted through `God.notifyByProcessId`, driven from
`lib/Client.js:551`, not through `God.notify` — which is why a grep of `God.notify` call sites misses
it. The walking skeleton observed `event="restart"` on the bus directly.

All arrive on the bus as `process:event` with `{ event, manually, process, at }`.

There is still **no** `errored` event and **no** memory-restart event (see F6); those must be derived.

### F4a — `exit` fires twice per restart ⚠️ *(live-observed)*

The skeleton captured this exact sequence for one probe-triggered restart of `pm_id=1`:

```
exit    status=stopping   restarts=0
exit    status=stopped    restarts=0
online  status=launching  restarts=1
restart status=online     restarts=1   manually=true
```

**Consequence:** naive counting of `exit` events double-counts. Crash-loop detection keyed on a raw
`exit` count will trip at half its configured threshold. Consumers must deduplicate on
`(pm_id, status)` or count only `status === 'stopped'`.

Note also that `status` is the status **at emit time**, so the `online` event carries
`status=launching`. Consumers must not treat the event's `status` as the settled state — read it from
`pm2.list()` instead.

### F4b — `manually: true` means "via the API/CLI", not "by a human" ⚠️ *(live-observed)*

The skeleton's probe module restarted an instance **programmatically** via `pm2.restart(pm_id)`, and
the resulting event carried `manually=true`.

**Consequence:** `manually` cannot be used to distinguish operator action from automated action. Any
requirement that suppresses alerts on `manually === true` would silently swallow every
probe-initiated restart — exactly the events that matter most. See REQ-AM-03a.

### F5 — `process:event` payload shape

`Utility.formatCLU()` returns `clone(process.pm2_env)` with **`env` deleted**. So the payload carries
`name`, `pm_id`, `status`, `restart_time`, `unstable_restarts`, `exit_code`, `pm_uptime`,
`exec_mode`, `namespace`, `versioning.revision`, log paths — but **not** the app's environment
variables.

**Consequence:** config stashed in `env` (F2) is *not* readable from an event payload. A consumer
needing it must call `pm2.list()` separately.

**Live-verified:** every `process:event` observed by the skeleton reported `env_present=false`.

### F6 — `max_memory_restart` emits no distinguishable signal

`lib/Worker.js` calls `God.reloadProcessId()` directly and logs to the daemon's own stdout. The
resulting bus traffic is indistinguishable from any other reload. The gap-analysis document lists
"memory restart" as an alert event; delivering it requires either sampling `monit.memory` before the
restart and inferring, or tailing PM2's daemon log. This is a **known-hard requirement**, not a free one.

### F7 — Custom typed messages are a first-class inter-module channel

In both `ClusterMode.js` and `ForkMode.js`:

```js
if (msg.data && msg.type) {
  return God.bus.emit(msg.type, { at, data, process: { pm_id, name, rev, namespace } });
}
```

And in `Daemon.js`:

```js
God.bus.onAny(function(event, data_v) {
  if ([...four axm: internals].indexOf(event) > -1) return false;
  that.pub.emit(event, Utility.clone(data_v));
});
```

So any PM2-managed process calling `process.send({ type, data })` has that message re-emitted on the
global bus under `type` as the event name, and forwarded to **every** external `launchBus` subscriber.

**This is the transport for the probe → alertmanager contract.** Two constraints:

1. Both `msg.data` and `msg.type` must be truthy, or it degrades to a generic `process:msg`.
2. The attached `process` descriptor is **reduced** to four fields. Everything else the consumer needs
   must be inside `data`.

**Live-verified — this is the single most important confirmation in this document.** The skeleton's
probe process emitted `pm2-probe:status`; a separate listener process received it via `launchBus`
with the payload fully intact:

```json
{"at":1793379233891,
 "data":{"v":1,"state":"fail","app":"demo-api","pm_id":1,"probe":"http","probe_kind":"liveness",
         "reason":"health check returned 503","consecutive":2,"threshold":2,"action":"restart"},
 "process":{"pm_id":3,"name":"probe","namespace":"default"}}
```

Note the `process` envelope identifies the **emitter** (`name: probe`), *not* the subject
(`demo-api`). Constraint 2 above is therefore load-bearing: all subject identity must live in `data`,
which is why `app` and `pm_id` are required fields in the contract (C4).

### F8 — The bus is fire-and-forget

The pub socket has no delivery guarantee, no acknowledgement, and no replay. A subscriber that is
down, restarting, or slow **misses events permanently**.

**Consequence:** `pm2-alertmanager` cannot be a pure bus subscriber and still claim reliable alerting.
It needs reconciliation against `pm2.list()` (see its REQ-AM-24).

### F9 — A long `PM2_HOME` silently wedges PM2 entirely ⚠️ *(found the hard way)*

PM2 binds `$PM2_HOME/rpc.sock` and `$PM2_HOME/pub.sock`. Linux caps unix socket paths (`sun_path`) at
**107 characters**. When `PM2_HOME` is long enough to exceed it:

- the daemon starts, writes `pm2.pid`, `module_conf.json` and `logs/`, and appears to be alive;
- **no `.sock` files are ever created** and no error is surfaced anywhere;
- every client — `ping`, `start`, `list`, even `kill` — blocks forever against a socket that will
  never exist;
- the orphaned daemon spins at ~100% CPU indefinitely.

Observed with a 148-character socket path. The failure presents as an unexplained hang with no
diagnostic whatsoever, and `pm2 kill` cannot clear it — orphans must be killed by PID.

**Consequences for both modules:**

- Integration-test harnesses and CI fixtures that set a custom `PM2_HOME` (a very common pattern, and
  the natural one for isolated tests) are the most likely place to hit this.
- Both modules' troubleshooting docs must name it: *"pm2 commands hang and never return"* →
  check `echo -n "$PM2_HOME/rpc.sock" | wc -c`.
- Test harnesses should assert the path length in setup and fail fast with a clear message rather
  than hanging the suite.

### F10 — Module install resolves peer dependencies ✅ *(verified)*

`pm2 install <name>` runs `npm install <name> --prefix $PM2_HOME/node_modules/<name>`
(`lib/API/Modules/NPM.js`, `getNPMCommandLine`), preferring `bun install --cwd` when bun is present.

Because npm 7+ installs peer dependencies automatically, declaring `pm2` as a **peerDependency**
rather than a dependency works: verified by packing `pm2-probe` and installing the tarball with
`--prefix`, after which `require.resolve('pm2')` from the installed module resolved correctly.

Two consequences worth knowing:

- **A second copy of PM2 is installed** inside the module directory (47 packages for `pm2-probe`).
  The declared production tree stays at 3 packages, but install footprint is not actually reduced —
  the real benefit of the peer declaration is avoiding a *version* lock, not avoiding the download.
- **Version skew is possible.** A peer range of `>=5` lets npm install a PM2 newer than the host
  daemon. The RPC surface we use (`connect`, `list`, `restart`, `launchBus`) is stable across 5–7,
  but the range should be narrowed if that ever stops being true.

---

## 2. The wire contract

Event name: **`pm2-probe:status`** — a single event type carrying a state transition. One event type
rather than several keeps the contract small and lets consumers filter on `data.state`.

Emitted by `pm2-probe` via `process.send({ type: 'pm2-probe:status', data: <payload> })`.

### Payload v1

```jsonc
{
  "v": 1,                        // contract version, integer, required
  "state": "fail",               // "pass" | "fail" | "recovered", required
  "app": "api",                  // PM2 app name, required
  "pm_id": 3,                    // PM2 process id, required
  "namespace": "default",
  "probe": "http",               // "http" | "tcp" | "exec" | "loop-lag", required
  "probe_kind": "liveness",      // "liveness" | "readiness", required
  "reason": "status 503, expected 200",
  "consecutive": 3,              // consecutive results in this state
  "threshold": 3,                // threshold that was crossed
  "latency_ms": 1204,
  "action": "restart",           // "restart" | "none", what the probe DID
  "rev": "a1b2c3d",
  "host": "web-01",
  "at": "2026-10-30T20:51:00.000Z"
}
```

### Contract rules

- **C1** — `v` is mandatory. Consumers MUST ignore events whose `v` they do not understand, and SHOULD
  log once per unknown version rather than per event.
- **C2** — Additive changes (new optional fields) do not bump `v`. Removing or retyping a field does.
- **C3** — Consumers MUST tolerate unknown extra fields.
- **C4** — The required fields are `v`, `state`, `app`, `pm_id`, `probe`, `probe_kind`, `at`. All
  others are optional and consumers must handle their absence.
- **C5** — `pm2-probe` MUST function fully with no consumer present. `pm2-alertmanager` MUST function
  (on native events alone) with no probe installed. Neither may hard-depend on the other.
- **C6** — The contract is published as a standalone zero-dependency package,
  **`@pm2-ops/probe-contract`**, containing the TypeScript types and a runtime validator. Both repos
  depend on it. This is the one shared artifact the independent-repo decision permits.

---

## 3. Cross-cutting non-functional requirements

Applies to both modules.

- **NFR-1 — Footprint.** Steady-state RSS < 60 MB; CPU < 1% of one core when idle. These are
  always-on daemons on servers whose owners chose PM2 over Kubernetes partly for weight.
- **NFR-2 — Never take the app down.** No unhandled rejection or uncaught exception may escape. A
  module crash-looping next to a healthy app is worse than the gap it fills.
- **NFR-3 — Dependencies.** Fewer than 15 transitive production dependencies. PM2 7 cut its own tree;
  a heavy module undercuts the pitch.
- **NFR-4 — Node support.** Node 18 LTS and above. Ship as CJS (PM2 `module:generate` scaffolds CJS
  and the daemon spawns modules directly); build from TypeScript to `dist/`.
- **NFR-5 — Platform.** Linux first-class. Windows best-effort, and explicitly documented as such —
  pm2-logrotate's reputation was damaged by silent Windows breakage.
- **NFR-6 — Observability of the module itself.** Both modules expose internal counters via
  `pmx.probe()` so `pm2 monit` shows whether they are working.
- **NFR-7 — Licence.** MIT. PM2 core is AGPL-3.0; these are separate processes talking over a public
  API. Confirm with counsel before any commercial offering (carried over from the gap analysis).
- **NFR-8 — Config validation.** Invalid config must fail loudly at boot with a specific message
  naming the offending key. Given F1's silent-discard behaviour, loud validation is a differentiator.

---

## 4. Open questions

| # | Question | Blocks | Proposed default |
|---|---|---|---|
| ~~Q1~~ | ~~Does `pm2 install <pkg>` work cleanly?~~ | — | **Resolved — see F10.** Unscoped `pm2-probe` chosen; peer deps resolve correctly |
| Q2 | Is tailing PM2's daemon log acceptable to detect memory restarts (F6)? | REQ-AM-05 | Ship without it in v1; document the gap |
| Q3 | Should the probe's HTTP endpoint (REQ-PR-20) bind by default? | Security | **No** — opt-in, loopback-only default |
| Q4 | Minimum viable alert channels for v1? | REQ-AM-10 | **Decided:** Slack + generic webhook only; generic webhook covers Teams/Discord, so native integrations wait for demand |
