# Weighted holder fairness

This document explains exactly what “fair” means in SPIN.

## The correct percentage

Chance is based on a wallet's share of the eligible weighted holder pool, not on
the token's raw total supply.

For every eligible wallet `a`:

`weight(a) = sum(balance(a, interval) × intervalDuration)`

`totalWeight = sum(weight(a) for every eligible wallet)`

For the first winner:

`chance(a) = weight(a) / totalWeight`

Example: a token has 1 billion supply. A treasury, burn address and LP hold 900
million and are excluded by the published rule. The eligible pool is 100 million.
A holder with 5 million has 0.5% of total supply, but 5% of the eligible pool, so
their first-draw chance is exactly 5%.

For several winners, SPIN removes a selected holder's weight before the next draw.
This prevents the same wallet from winning twice. The next draw uses the remaining
weight, so probabilities are recalculated from the remaining eligible pool.

Every settled winner is excluded from the next complete round. This one-round
cooldown is the same for every wallet and comes from public winner events; it does
not alter the proportional formula for wallets eligible in a given round.

## Why time-weighted balances

A single snapshot lets someone borrow or buy tokens briefly just before the draw.
SPIN therefore uses a published qualification window. Holding tokens longer creates
more weight; buying them at the end creates proportionally less weight.

The default calculation uses the token balance that applied during each interval
between transfers, multiplied by the interval's elapsed time. Its source is the
token's on-chain transfer history and the chain's block timestamps. The complete
calculation input and output are published before the holder root locks.

## Snapshot protocol

A snapshot is not a list supplied by the developer. It is a fixed, reproducible
calculation that SPIN builds automatically from the linked token's public on-chain
transfer history. These inputs are locked before the qualification window starts:

- token contract address and chain ID;
- `startBlock` and `endBlock` of the qualification window;
- minimum eligible balance, if any;
- hash of the exclusion list and its rules;
- hash of the published calculation/version specification;
- root review period and required confirmation depth.

The backend first reads the token balance at `startBlock`, then processes every
on-chain `Transfer` event through `endBlock`. Between two transfers, a holder's
balance is constant. The backend multiplies that balance by the elapsed time until
the next transfer and sums the result. This produces the time-weighted balance.
No developer uploads, edits or hand-picks the holder list.

After `endBlock` has enough confirmations, the backend publishes a snapshot manifest
and the complete sorted holder-weight list. The manifest contains the block hashes,
raw event range, static-exclusion hash, winner-cooldown-list hash, calculation version, total weight and
Merkle-sum root. The vault accepts a root only after its public review period ends.

No project owner can move `startBlock`, `endBlock`, exclusions or the calculation
method after the window begins. A user can independently replay the same transfer
events and obtain the same list and root.

## What the Merkle-sum root proves

The root seals every wallet's calculated weight and the total weight. Once locked,
it cannot be changed. A winning proof proves three things to the vault:

1. the winner wallet and its weight were in the locked list;
2. the root total includes that weight;
3. the Dice-derived random position falls inside that wallet's weight interval.

This makes winner selection exactly verifiable against the locked list.

## Completeness: the important limit

A root proves that listed data has not changed. It does not by itself prove that a
wallet was not wrongly left out before locking. Claiming that it does would be false.

SPIN supports two fairness levels:

1. **External token mode:** SPIN indexes a standard ERC-20's transfer history,
   publishes the full weighted list and opens a review period before locking. Anyone
   can reproduce the list from chain data and report an omission. This is transparent
   and practical, but relies on the published indexing process for completeness. It
   must not be marketed as a fully trustless completeness guarantee.
2. **Checkpoint token mode:** a token exposes historical, on-chain balance
   checkpoints or a dedicated SPIN eligibility interface. The vault can verify
   historical weights directly. This gives the strongest trust model, but requires
   the token project to support the interface.

For a fully trust-minimized holder set, SPIN needs an opt-in eligibility registry or
a token integration. Each holder registers before the window closes; the contract
can then verify every registered holder's historical balance through checkpoints.
No off-chain service can omit a registered eligible wallet. This is the recommended
mode for projects that require the strongest possible guarantee.

## Product rule

SPIN may describe a jackpot as **provably fair** only in checkpoint token mode with
the opt-in eligibility registry. External token mode can be described as public,
reproducible and reviewable, but it has an explicit indexer-completeness assumption.

OpenZeppelin's `ERC20Votes` is an example of a checkpointed token design, although
its vote delegation behavior must be considered before using it as a holder-balance
source. [OpenZeppelin ERC20Votes documentation](https://docs.openzeppelin.com/contracts/4.x/api/token/erc20)

## Automatic payout

After Dice resolves, SPIN automation sends the public Merkle-sum proof to the vault.
The vault verifies it and pays the selected holder directly. The automation service
does not control winner selection, payout amount or payout destination. If it is
offline, anyone can submit the same proof and get the same automatic payout result.
