# Contributing to SPIN PROTOCOL

## Local setup

Clone with the pinned OpenZeppelin dependency:

```sh
git clone --recurse-submodules https://github.com/SpinprotocolOnchain/SpinProtocol.git
cd SpinProtocol
npm ci
```

For an existing clone, run `git submodule update --init --recursive` once.

## Required checks

Run these before opening a pull request:

```sh
npm run typecheck
npm test
npm run contracts:fmt
npm run contracts:test
```

## Change rules

- Keep protocol rules in `backend/src/domain` free of RPC, filesystem and UI concerns.
- Keep network-specific code inside an adapter.
- Add a regression test for every behavior change.
- Do not add keys, RPC URLs with credentials, deployment private keys or generated build output.
- Any change to payout, eligibility, randomness, accounting or access control must update the relevant document in `docs/`.
- Do not deploy from a pull request. Production deployment requires a separate review and audit process.
