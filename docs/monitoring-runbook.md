# Monitoring and recovery runbook

Run these checks against the deployment manifest's pinned addresses. Alerting must
be independent of the snapshot publisher and the Dice requester.

## Alerts

- **Snapshot deadline:** alert when a configured round has less than one review
  period remaining before `snapshotExpiresAtBlock`; expire and roll it forward if
  no reviewed root can be approved.
- **Dice request:** alert immediately for a pending sequence. If it remains pending
  longer than Dice's documented refund delay, trigger `refundDice(roundId)` and
  investigate the provider before retrying.
- **Payout progress:** alert when a resolved sequence has unpaid winner ordinals.
  Anyone may submit the public proof, so the recovery worker must not need a winner
  signature or private key.
- **Accounting:** after every `DepositAllocated`, `DiceRequested`, `DiceRefunded`,
  `WinnerPaid` and rollover event, reconcile each round's pot and reserved balances
  with the vault getters. Any mismatch is a severity-one incident.
- **Configuration:** run the deployment-manifest validator before activation and
  daily thereafter. A changed code hash, controller link, router link or factory
  owner is a severity-one incident; stop funding until resolved.

## Recovery rules

Do not change a finalized root, winner count or payout amount during recovery.
Do not subsidize a Dice fee from another round. If the fee is unaffordable, keep the
round pending until a documented subsidy policy exists. If a snapshot is unavailable,
use the committed expiry and immediate-next-round rollover path.

## Evidence

Record alert time, chain block, transaction hash, manifest revision, affected round,
before/after vault values and the operator decision. Publish this record with the
round artifact after resolution.
