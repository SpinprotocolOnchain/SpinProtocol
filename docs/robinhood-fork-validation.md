# Robinhood fork validation gate

This is the required release gate between local tests and any deployment or funding
on Robinhood Chain. It is a reproducible verification procedure, not permission to
deploy.

## Required inputs

- an archive-capable Robinhood Chain RPC endpoint in `EVM_RPC_URL`;
- a fixed fork block and its block hash, recorded in the validation report;
- the exact WETH, Dice oracle and Dice provider addresses proposed for the deployment;
- the reviewed bytecode or verified source for each of those addresses;
- the address and policy of a production multisig or timelock that will act as the
  snapshot approver; and
- a candidate external ERC-20 that meets the v1 token policy.

Do not use an EOA as the snapshot approver. Do not test an unpinned `latest` block;
the same report must be repeatable against the recorded block hash.

## Running the gate

Copy the fork-specific variables from `.env.example` into a private environment,
replace every placeholder with reviewed values, then run:

```sh
sh contracts/evm/script/validate-robinhood-fork.sh
```

The runner first obtains the configured block hash directly from the RPC and compares
it with `ROBINHOOD_FORK_BLOCK_HASH`. It exits before Foundry starts if they differ.
It then enables the otherwise skipped `RobinhoodForkValidationTest`. The test checks
the child-chain clock, required deployed bytecode and factory wiring against that
same fixed fork.

## Required assertions

1. The RPC reports chain ID `4663`, and its reported block hash equals the recorded
   fork hash.
2. `RobinhoodClock.currentBlock()` equals the Robinhood RPC child-chain block number
   at the fork. This verifies the ArbSys precompile behaviour used by qualification,
   finality and expiry boundaries.
3. `SpinIntegrationFactory` deploys the round book, vault and controller in one
   transaction. Confirm `vault.factory()`, `vault.settlementController()` and the
   controller's configured vault all match the emitted child addresses.
4. The factory-created fee router can fund only an announced round and cannot wire a controller,
   reserve funds or redirect a payout.
5. A publisher can propose a root but cannot finalize it. The configured multisig or
   timelock can finalize only after review, reject a bad proposal and allow expiry
   after the committed deadline.
6. A Dice request uses the exact deployed ABI, pays the live quoted fee, accepts a
   callback only from the configured oracle/provider and restores the same round
   state on refund.
7. A proof pays only the selected address; a duplicated wallet leaf and a repeated
   payout attempt both revert.
8. The backend builds the same artifact twice from the fixed range, rejects a
   changed cutoff hash, and derives cooldowns only from `WinnerPaid` events at the
   manifest's controller address and deployment block.

## Evidence to retain

Store a dated report with the source revision, Foundry and Node versions, fixed fork
block/hash, command output, transaction traces, contract bytecode hashes, ABI hashes
and the resulting deployment manifest. A second operator must reproduce the result
from the report before any deposit route is enabled.

## Release rule

Fork validation passing does not replace an independent audit. The deployment remains
blocked until the v1 token allowlist, approver operating procedure, monitoring and
recovery-gas policy are approved and an independent smart-contract audit is complete.
