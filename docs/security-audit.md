# SPIN PROTOCOL security and functional review

Reviewed: 2026-09-09. Scope: the current EVM contracts, TypeScript snapshot
pipeline, local tests, CI configuration and documented Dice integration. This
is an engineering review, not an independent smart-contract audit.

## Deployment decision

**Do not deploy or accept real funds yet.** The payment arithmetic, round-pot
isolation, WETH intake and proof verification have useful local coverage, but
the protocol still has critical trust and liveness gaps around the participant
list and deployment wiring.

## Findings requiring design and code changes

### Resolved in v1: a publisher cannot independently finalize a winner list

`SpinRoundBook.proposeSnapshot` still accepts a publisher-supplied root, weight
and holder count, because an arbitrary external ERC-20 cannot prove full holder
history on-chain. A publisher can no longer finalize that root. Each configured
round stores a separate code-bearing snapshot approver, intended to be a
multisig or timelock. That approver alone may approve after review or reject and
replace a root before its expiry.

The public review period is now combined with a veto, replacement and expiry
path. A round cannot remain pending forever because anyone may expire it after
the precommitted deadline and roll its pot to the next announced round.

This is intentionally an administered external-token mode and must be marketed
that way. A multisig/timelock compromise can still approve a bad root. The
future checkpoint/opt-in mode remains the route to trust-minimized eligibility.

### Resolved in v1: deployment wiring is factory-controlled

`SpinIntegrationFactory` creates the round book, vault and settlement controller
and performs their one-time wiring in the same transaction. The vault records
its creating factory and accepts `setSettlementController` only from that
factory. The fee router can fund an announced round but has no settlement
authority. Rollover is permissionless and can only target the immediate next
announced round.

Deployment manifests must still record and verify factory bytecode, constructor
arguments and each child address before any integration accepts deposits.

### Resolved in v1: contracts and backend use Robinhood child-chain heights

`RobinhoodClock` calls the ArbSys precompile for the child-chain height, the same
height returned by Robinhood RPC block and receipt APIs. It falls back to
`block.number` only when the precompile is absent, which is used for local tests.

Fork verification against Robinhood remains required before deployment.

### Resolved in v1: winner cooldown is event-derived

The snapshot reader queries `WinnerPaid` events from the configured settlement
controller address for the immediately preceding round. The caller no longer
supplies a winner list. Event source range and controller deployment block are
part of the build input.

The reader validates event block hashes against canonical blocks. A deployment
manifest must pin the controller address and deployment block.

### Resolved in v1: a missing snapshot has a deterministic expiry path

Every round commits a snapshot-expiry period that must be at least its review
period. Anyone can expire a still-unfinalized round after that deadline; anyone
can then roll it into the immediately next announced round.

The source pot cannot be redirected to an arbitrary destination or withdrawn.

## Important hardening work

- The on-chain round stores only a configuration hash; it does not recompute or
  validate token, WETH, router, exclusion or calculation inputs. The factory
  must bind the full configuration and prevent an arbitrary hash from being
  announced.
- Eligibility supports only well-behaved ERC-20s. Rebasing, reflection,
  transfer-tax, proxy-upgradable, blacklisting or non-standard tokens can make
  `Transfer` history differ from effective balances. Add an allowlist and
  bytecode/version checks, or restrict v1 to immutable standard tokens.
- The factory now enforces a contract-level maximum of 32 winners and records that
  cap in each round book. Validate its real Robinhood gas cost during fork testing
  before enabling any production integration.
- The Dice oracle and provider are a liveness dependency. Dice documents that
  an unrevealed request becomes refundable; repeated withholding can still
  delay settlement and requires gas-paid recovery. Monitor provider capacity,
  callbacks and fee changes, and define who funds recovery gas.
- The Oracle fee can rise above the remaining round pot. The current code safely
  refuses to reduce promised prizes, but the round then waits indefinitely.
  Decide whether a separate immutable subsidy policy is needed; do not silently
  take funds from another round.
- The full participant list can be very large. Reading all historical transfers
  and `eth_getCode` per holder is expensive and RPC-dependent. Add archive-RPC
  requirements, resumable checkpoints, deterministic chunk manifests and
  independent reproduction tooling.
- A single EOA can use multiple wallets. The per-wallet cooldown cannot detect
  common ownership; this must be stated clearly in product language.

## Confirmed protections

- Only the configured router can deposit, and WETH balance deltas are checked.
- A round's deposits close after its qualification cutoff and settlement uses
  the recorded round pot, not raw token balance.
- Dice fees, reservations, refunds and prize payments are isolated per round.
- A resolved winner cannot receive a second prize within that round, including
  when a malformed root lists the same wallet more than once.
- Proof verification is bounded by tree height; winner selection is weighted,
  deterministic from Dice output and without replacement.
- The snapshot pipeline now rejects a wrong chain, detects block-hash changes
  during collection, pins historical code checks to the cutoff block hash, and
  rejects non-canonical RPC transfer data.

## Validation performed

- Backend typecheck and 47 unit tests passed.
- Contract CI profile: 38 tests passed, including 2,000 fuzz inputs.
- Regression coverage confirms factory-only wiring, independent snapshot
  approval, expiry/rollover and duplicate-wallet payment rejection.

## Recommended order

1. Validate the factory, child-chain clock and Dice adapter against a Robinhood fork.
2. Add an integration runner, deployment manifest validation, monitoring and
   invariant/fork tests.
3. Obtain an independent audit and remediate all findings before accepting
   funds.
