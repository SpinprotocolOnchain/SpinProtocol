# Dice integration boundary

SPIN will use DiceEntropy v10 on Robinhood Chain solely for winner randomness. The
snapshot, holder weights, eligibility filters and prize amounts are SPIN rules; Dice
does not calculate any of them.

The reviewed mainnet adapter is deliberately small. Its only callable Dice functions
are the active V2 request method, the current fee query and the requester-only refund
method. This avoids inheriting a large external SDK surface into the payout vault.

## Fixed production coordinates

- Chain: Robinhood Chain, `4663`.
- DiceEntropy v10: `0xd8a0680e7699526b57140ed4eafdcc7219dc0a0c`.
- Current default provider: `0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6`.
- Callback gas limit: `200,000`, confirmed against the current minimal callback;
  measure it again after any callback-code change.

Those addresses are isolated in `DiceRobinhoodConfig.sol`. A future Dice version,
different provider, or another chain requires a new reviewed adapter and test suite;
it must not silently change a deployed vault's randomness source.

## Failure behaviour

Dice uses commit-reveal. The provider cannot choose a completed random value after
its hash-chain commitment, but it can fail to reveal. Dice documents a requester-only
refund after its configured delay. SPIN's vault must keep the round pending in that
case, let anyone trigger the refund, and allow a fresh randomness request using the
same sealed snapshot. It must never replace the root or alter payouts while retrying.

If Dice's callback runs out of gas or reverts, Dice records a failed callback and
allows the reveal callback to be retried. Dice v10 calls `_entropyCallback`; SPIN's
implementation only records the random word and transitions the request. Prize
transfers are executed separately so a receiver cannot block the entire settlement.

Sources: [Dice developer documentation](https://github.com/diceprotocol/dice-protocol-docs/blob/main/developer-docs.md) and [Dice verification guide](https://diceprotocol.world/docs/verification/).
