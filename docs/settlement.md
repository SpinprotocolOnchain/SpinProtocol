# Dynamic settlement formula

All calculations use unsigned integers in WETH wei. No USD conversion or floating
point calculation participates in settlement.

## Inputs locked for a round

- `P`: WETH already credited to this project's jackpot after the immutable SPIN
  protocol-fee allocation at deposit time;
- `minimumPayout`: lowest payout allowed for one winner;
- `maximumWinners`: a positive configured uint32 limit (production gas limits still need measurement);
- `holderCount`: number of eligible wallets in the locked Merkle-sum root;
- `totalWeight`: sum of all eligible holder weights in the same root.

`P` is an internal accounting value updated only through the vault's deposit or
fee-router function. Settlement must not use raw `WETH.balanceOf(vault)`, because
an unsolicited token transfer could otherwise change a draw.

## Step 1: reserve Dice cost

`O` is the exact fee returned by Dice in the request transaction. The current docs
list `0.000025 ETH`, but code must read the oracle because underpayment and
overpayment both revert.

The vault unwraps exactly `O` WETH and sends that ETH with `requestV2`. If `P <= O`,
the request is rejected and the sealed pot stays unchanged.

## Step 2: calculate winners and payouts

`J = P - O`

`N = min(maximumWinners, floor(J / minimumPayout), holderCount)`

If `N = 0`, no Dice call or oracle-fee transfer occurs. Anyone can roll a pot below
`minimumPayout` into the immediately next configured, open round after snapshot
finalization.
If the pot meets `minimumPayout` but cannot also cover the oracle fee, it waits
for a lower fee.
Therefore, `N` can never exceed the eligible holder count.

If `N > 0`:

`payoutPerWinner = floor(J / N)`

`R = J - N * payoutPerWinner`

All winners receive `payoutPerWinner`. After all winners are paid, anyone can carry
`R` into the immediately next open round without another protocol fee. Equal payouts are transparent and auditable. A ranked-payout formula is a
separate feature that needs its own fixed, tested specification.

The contract enforces the conservation identity `J = N × payoutPerWinner + R` for
every possible integer input, including a pot too small for one payout. There are
no floating-point values and no hidden rounding rule.

The protocol fee was allocated before this round received `P`, so a failed draw does
not alter creator revenue, the `$SPIN` holder jackpot or the buyback reserve.

Before requesting Dice, the vault moves exactly `N * payoutPerWinner` out of the
sealed round pot into this round's settlement reserve. Later fee deposits must
explicitly target a later announced round. They can never increase, reduce or otherwise alter
the amount due to winners of an already sealed round.

## Step 3: choose weighted, unique winners

Each holder has a time-weighted balance `w`. The root stores the total:

`W = sum(w for every eligible holder)`

The standard weight is the holder's balance multiplied by the time it was held
inside the published qualification window, summed across the window. The backend
derives it from on-chain transfer history and publishes the complete input/output
file before locking. A single-block balance snapshot is not used for this rule.

For the first draw, the vault derives:

`r` is derived from `keccak256(randomWord, roundId, winnerOrdinal, retryNonce)`.
SPIN rejects the tiny overflow tail before applying the modulo operation, then uses
`r % W`. This rejection-sampling step removes modulo bias rather than merely making
it very small.

A Merkle-sum proof identifies the one holder whose cumulative weight interval
contains `r`. That proof also proves the holder's weight and the total `W`.
Consequently, a holder with 5% of `W` has exactly 5% selection chance in this draw.
The full weighted list is public, so any party can submit the required proof; this
prevents the backend from controlling availability after the random word exists.

After selection, the contract deterministically updates the Merkle-sum root by
setting that holder's weight to zero. The next draw uses the remaining total weight.
This is weighted selection without replacement, so a holder cannot win twice in one
round. The contract performs bounded work per winner and never scans all holders.

SPIN automation submits the selected holder's proof to an automatic payout function.
The function verifies the proof, records the paid holder and transfers WETH directly
to that holder in the same transaction. The automation wallet cannot receive the
prize or alter its amount. Any party can submit the same public proof if automation
is unavailable.

## Step 4: timeout

If Dice does not reveal, anyone can trigger its refund path after the documented
delay. Rewrap returned ETH to WETH, restore both the Dice fee and the untouched
settlement reservation to the same sealed round pot. Retain the original winner
count and payout on retry; never invent replacement randomness. A higher oracle
fee cannot reduce those prizes or consume another round's funds. See
[round lifecycle](round-lifecycle.md) for retry and rollover limitations.

There is no unclaimed-prize path: selected winners are paid automatically.

## Example

For `P = 1 WETH`, `O = 0.000025 WETH`,
`minimumPayout = 0.1 WETH`, `maximumWinners = 10` and `holderCount = 200`:

1. `J = 0.999975 WETH`.
2. `N = min(10, floor(0.999975 / 0.1), 200) = 9`.
3. Each winner receives `0.111108333333333333 WETH`.
4. The 3 wei remainder rolls into the next round.
