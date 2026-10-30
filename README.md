# pm2-ops-contract

Shared platform constraints and the wire contract for the **pm2-ops** module suite.

The modules in this suite are deliberately **independent repositories** - they install
separately, version separately, and neither hard-depends on the other. What they do share is
a set of facts about how PM2 actually behaves, and one event payload that crosses between
them. Those live here rather than being duplicated into each repo and left to drift.

## Contents

| File | What it is |
| --- | --- |
| [`00-platform-and-contract.md`](./00-platform-and-contract.md) | Verified PM2 platform findings (F1-F13) and the `pm2-liveness:status` wire contract |


Each module's own requirements live with its code:

- [`pm2-liveness/docs/requirements.md`](../pm2-liveness/docs/requirements.md) - the producer
- [`pm2-alertmanager/docs/requirements.md`](../pm2-alertmanager/docs/requirements.md) - the consumer
- [`pm2-shipper/docs/requirements.md`](../pm2-shipper/docs/requirements.md) - rotation and shipping

## Why a contract document rather than a shared package

`pm2-liveness:status` is a **wire** contract, like a webhook payload - not a shared library type.
Consumers carry their own copy of the type and a small validator, exactly as they would for any
JSON they receive over a bus. A published `@pm2-ops/probe-contract` package was considered and
rejected for v1: three npm packages before either module has a user is premature, and a version
field in the payload already does the job a shared package would.

This document is the normative definition. The copy in `pm2-liveness/src/events/contract.ts` and the
one in the eventual `pm2-alertmanager` are implementations of it.

## Status of the findings

Every finding in `00-platform-and-contract.md` is marked with how it was established. Several
were **corrected after running PM2 rather than reading its source** - notably that a `restart`
event exists, that `exit` fires twice per restart, and that `manually: true` means "via the
API/CLI" rather than "by a human". Source inspection alone got two of those wrong, so prefer a
live check before trusting a new claim added here.

Verified against **PM2 7.1.1**.

## Licence

MIT - see [LICENSE](./LICENSE).

## Conformance suite

[`conformance/run.sh`](./conformance/run.sh) tests the two modules **together**, through
paths that neither module's own tests can reach:

- the real `pm2 install` path - tarball install, `pmx_module`, `module_conf.json`, and the
  restart that `pm2 set` triggers;
- the wire contract **across process boundaries** - `pm2-liveness` emits, `pm2-alertmanager`
  consumes, and a local webhook collector records what a human would have been sent.

```bash
(cd ../pm2-liveness && npm run build) && (cd ../pm2-alertmanager && npm run build)
./conformance/run.sh
```

It asserts that breaking one cluster instance restarts only that instance and produces one
`probe-fail` alert followed by a resolution notice, and that an app restarting 15 times
produces 2 alerts rather than 15.

Both bugs it found on its first run were in the test itself, not the modules - including
one where the cluster guard correctly refused to probe an app whose instances shared a
port. That is the guard working, and it is worth knowing the suite is sharp enough to
catch its own mistakes.
