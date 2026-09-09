# Round lifecycle

This is the enforced state order for every project jackpot round. A later state
cannot be skipped or moved backwards.

```text
Configured → Snapshot proposed → Snapshot finalized → Dice requested → Settled
     └──────────────────────→ Expired → Rolled into next round
```

`SpinRoundBook` enforces the first three states. `SpinSettlementController` enforces
the Dice request, the sealed payout budget and every later winner payment.

## 1. Configure before qualification begins

The project administrator opens the next sequential round before its qualification
start block. The contract stores:

- the hash of the complete round configuration;
- qualification start and end blocks;
- required finality blocks after the end block; and
- the public review and snapshot-expiry lengths in blocks; and
- the independent, code-bearing snapshot approver for that specific round.

The configuration hash is built from the token, linked fee-router, WETH asset,
minimum payout, maximum winner count, qualification window, static exclusions and
calculation version. It is the same commitment used by the backend snapshot builder.

## 2. Propose only after finality

The snapshot publisher recorded inside that specific round may propose one manifest and Merkle-sum root only
after:

`Robinhood child block ≥ qualification end block + finality blocks`

The proposal includes the manifest hash, root, total eligible weight and eligible
holder count. Zero values are rejected. The contract calculates and stores the exact
block at which the review ends.

Changing the publisher only applies to rounds configured later. It cannot take over
an already announced qualification window.

## 3. Public review, independent approval and expiry

The root stays in `Snapshot proposed` throughout the entire configured review period.
Only the separate snapshot approver committed to that round may finalize it after
the review period. The approver must be a contract, normally a multisig or timelock;
it can reject a proposal so the publisher can submit a corrected replacement.

The configured snapshot expiry is at least as long as the review period. Anyone may
expire an unfinalized proposal after that deadline and roll its unreserved pot into
the immediately next configured, open round. This gives failed publishing or review
a deterministic recovery path.

For an external ERC-20, review and approver verification remain the protection
against an indexer omitting a holder: the root itself proves the published list is
unchanged, but cannot by itself prove every historical holder was included. SPIN
must therefore publish the manifest, raw transfer range and full holder-weight list
before finalization. The product must describe this as administered external-token
mode, not fully trustless completeness.

For the future native `$SPIN` token, SPIN will use an on-chain historical-balance
design so eligibility can be verified directly instead of relying on an indexer for
completeness.

## 4. Request Dice and settle winners

After finalization, anyone may request Dice when the recorded project pot supports
at least one minimum payout plus the live Dice fee. The controller binds the Dice
sequence to the exact finalized root and reserves the entire payout budget before
the request. Dice delivers the random word through its v10 `_entropyCallback`.

Each subsequent public Merkle-sum proof pays exactly one determined winner in WETH
and removes that winner from the remaining weight. The winner does not claim or
sign anything. If Dice does not reveal, its requester-only refund restores both the
fee and untouched payout reservation to the project pot for the same sealed round.

## Round-specific funding and retries

Deploy through `SpinIntegrationFactory`. It creates the round book, a dedicated
non-custodial fee router, vault and controller, then wires them in the same
transaction. The vault accepts one-time wiring only from its creating factory; the
router can only pull approved WETH into an open round and has no withdrawal path.
The previous `fundJackpot(amount)` entry point is replaced by
`fundRoundJackpot(roundId, amount)`. All reservations and refunds carry a round ID.
This is a breaking interface change for deployment scripts and integrators.

The router may fund an announced round up to and including its qualification end
block. From the following block, deposits revert even if nobody has called
`sealRoundPot` yet. The router must choose a later announced round for new revenue;
the contracts do not automatically route rejected deposits. Finality must be at
least one block, preventing snapshot proposals during the last funding block.
The configured finality depth still needs chain-specific validation before deployment.

`accountedPot` is the sum of unreserved round pots; settlement reads only
`roundPot(roundId)`. Winner reservations are separately tracked per round.
Unsolicited WETH transfers do not credit any round.

A refund restores the fee and payout reservation to the same sealed round. Its
winner count and payout remain fixed for retries. A cheaper oracle request leaves
the saving in that round; an unaffordable higher fee blocks the retry rather than
reducing prizes or spending another round's balance. This can delay settlement
until the fee falls; there is currently no separate oracle-fee subsidy path.

Anyone may call `rolloverRound` to move a completed round's remainder, an expired
round's unreserved pot, or an unrequested round below its minimum payout into the
immediately next announced, still-open round. No protocol fee is charged again.
Pending and refunded draws cannot roll over. A pot meeting the minimum payout but
unable to cover the oracle fee waits for an affordable fee; fee changes cannot be
used to cancel that draw. A rolled-over source round cannot request randomness again.
