# pm2-ops-contract

Shared platform constraints and the wire contract for the **pm2-ops** module suite.

The modules in this suite are deliberately **independent repositories** - they install
separately, version separately, and neither hard-depends on the other. What they do share is
a set of facts about how PM2 actually behaves, and one event payload that crosses between
them. Those live here rather than being duplicated into each repo and left to drift.

## Contents

| File | What it is |
| --- | --- |
| [`00-platform-and-contract.md`](./00-platform-and-contract.md) | Verified PM2 platform findings (F1-F17) and the `pm2-liveness:status` wire contract |


Each module's own requirements live with its code:

- [`pm2-liveness/docs/requirements.md`](../pm2-liveness/docs/requirements.md) - the producer
- [`pm2-alertmanager/docs/requirements.md`](../pm2-alertmanager/docs/requirements.md) - the consumer
- [`pm2-shipper/docs/requirements.md`](../pm2-shipper/docs/requirements.md) - rotation and shipping
- [`pm2-secrets/docs/requirements.md`](../pm2-secrets/docs/requirements.md) - secret injection
- [`pm2-release/docs/requirements.md`](../pm2-release/docs/requirements.md) - health-gated deploys,
  a second consumer of the same contract

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

## Test lab

[`lab/`](./lab) runs every module in the suite together against one live PM2 daemon,
installed the way a user installs them: `pm2 install` from a packed tarball, not a
`require` of the working tree.

```bash
PM2_HOME_OVERRIDE=/tmp/plab ./lab/lab.sh        # every scenario
PM2_HOME_OVERRIDE=/tmp/plab ./lab/lab.sh 60 61  # just these
```

Sixteen scenarios, 82 assertions. It exists because it keeps finding things the modules'
own test suites cannot. Scenario 60 failed 7 of 11 assertions while every unit test in
`pm2-release` was green, because the CLI built a gate object with one field undefined and
the health check was silently never run. Twice the lab itself was the thing at fault,
going green while the app under test had never started.

Scenario 61 is the only test anywhere that proves two modules actually talk:
`pm2-liveness` judges a reloaded instance, and `pm2-release` reads that verdict off the
bus and reverts the release on the strength of it.

`PM2_HOME` must stay short. PM2 binds `$PM2_HOME/rpc.sock` and Linux caps unix socket
paths at 107 characters; over that the bind fails silently and every `pm2` command hangs
forever. The lab asserts this up front rather than hanging.

## Licence

MIT - see [LICENSE](./LICENSE).
