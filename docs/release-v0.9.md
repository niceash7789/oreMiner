# V0.9 release readiness

## Purpose

Track the proposed V0.9 single-turtle prerelease against the release gates in [MINER_PLAN.md](../MINER_PLAN.md).

## Implemented behavior and entry points

The current software provides `miner`, `miner status`, `miner resume`, and `miner home`, plus the in-game installer and autostart hook. See [runtime baseline](runtime-baseline.md) and [controlled gallery test](home-test.md) for behavior and operator procedure.

## Invariants and assumptions

V0.9 follows the MVP's known-route fuel and return policy, durable action intent, and fail-closed uncertain-pose rule. The release assumes the documented single turtle, orientation, and chest layout. `MINER_PLAN.md` remains the authoritative specification and release checklist.

## Dependencies and current limitations

The software test suite can establish only the mocked Gates A–E. Physical confirmation of Gates B–E and the multi-trip, forced-reboot Gate F require a controlled CC:Tweaked world. The open geometry and right-side torch checklist rows also require direct observation. The F07 startup-fuel wording conflict recorded in [STATUS.md](STATUS.md) needs a product decision before claiming the MVP release gates complete.

Do not advertise V0.9 as an unattended release or check the physical gates until the operator records the results from [home-test.md](home-test.md).
