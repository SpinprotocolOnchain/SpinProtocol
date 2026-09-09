# Round lifecycle

This is the enforced state order for every project jackpot round. A later state
cannot be skipped or moved backwards.

```text
Configured → Snapshot proposed → Snapshot finalized → Dice requested → Settled
```

`SpinRoundBook` enforces the first three states. `SpinSettlementController` enforces
the Dice request, the sealed payout budget and every later winner payment.

## 1. Configure before qualification begins

The project administrator opens the next sequential round before its qualification
start block. The contract stores:

- the hash of the complete round configuration;
- qualification start and end blocks;
- required finality blocks after the end block; and
- the public review length in blocks.

The configuration hash is built from the token, linked fee-router, WETH asset,
minimum payout, maximum winner count, qualification window, static exclusions and
calculation version. It is the same commitment used by the backend snapshot builder.

## 2. Propose only after finality

The snapshot publisher recorded inside that specific round may propose one manifest and Merkle-sum root only
after:

`current block ≥ qualification end block + finality blocks`

The proposal includes the manifest hash, root, total eligible weight and eligible
holder count. Zero values are rejected. The contract calculates and stores the exact
block at which the review ends.

Changing the publisher only applies to rounds configured later. It cannot take over
an already announced qualification window.

## 3. Public review then permissionless finalization

The root stays in `Snapshot proposed` throughout the entire configured review period.
Anyone may call finalization once that period ends. It does not depend on the backend
being online or on the project administrator taking action.

For an external ERC-20, review remains the protection against an indexer omitting a
holder: the root itself proves the published list is unchanged, but cannot by itself
prove every historical holder was included. SPIN must therefore publish the manifest,
raw transfer range and full holder-weight list before finalization. The product may
only call this mode public and reproducible, not fully trustless completeness.

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
