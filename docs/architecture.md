# Architecture

SPIN PROTOCOL is a B2B jackpot wrapper for Robinhood Chain. An integrator connects
its fee flow to a vault. The vault calculates whether a draw can settle, the number
of winners and the payout amount from an on-chain formula.

The integrator is the protocol customer. A player is an eligible payout recipient.

## Policy inputs

For future rounds, an integrator configures a WETH fee source, `minimumPayout`,
`maximumWinners`, eligibility rules and a qualification window.

The contract derives the actual winner count and payout from those inputs and
recorded WETH deposits. It never accepts these values from a backend job. When a
draw begins, it locks the inputs, weighted-holder root, total eligible weight and
eligible-holder count.

## Settlement

The formula is defined in [settlement.md](settlement.md). It reserves the exact
Dice fee, derives winners from the minimum payout, pays winners equally and carries
integer remainder into the next round.

If the formula derives zero winners, the vault leaves the round open. No Dice call
or protocol-fee transfer occurs; the recorded pot rolls over.

The first on-chain boundary is an immutable WETH intake vault. Only the linked
fee-router may fund it. Each accepted deposit is immediately and deterministically
allocated 97.5% to the project pot, 1% to the creator treasury, 1% to the `$SPIN`
holder jackpot and 0.5% to the buyback reserve. It deliberately has no owner
withdrawal function. `SpinSettlementController` is the only component allowed to
reserve or pay the recorded project pot after its payout checks pass.

The `SpinRoundBook` enforces the pre-settlement order: configure before the window,
propose after finality, then finalize after public review. See
[round-lifecycle.md](round-lifecycle.md).

## Randomness and eligibility

DiceEntropy v10 provides the random word through a small isolated consumer adapter
using its `_entropyCallback` entry point. The controller draws from a Merkle-sum tree
of eligible holder weights. For the first winner, a wallet's probability is exactly:

`holderWeight / totalEligibleWeight`

After a winner is selected, its weight is removed from the tree before the next
draw. This gives weighted selection without replacement: a holder cannot win twice
in the same round. `N` is capped by the eligible-holder count and the contract never
iterates over all holders.

The standard eligibility weight is a time-weighted token balance over a published
qualification window. This resists short-lived balance manipulation better than a
single block snapshot. The exact window, exclusions and weight formula are locked
before the round begins.

Dexch.art is optional read-only data for UI or monitoring. It never determines
eligibility, payouts, settlement or trading.

## Security boundaries

- The first release supports WETH only.
- A locked round's policy, holder root, holder count and payout rules are immutable.
- Automatic payouts use checks-effects-interactions and reentrancy protection.
  The verified winner wallet and amount are fixed before WETH is transferred.
- Every Dice request maps to one pending round; callbacks must match the configured
  Dice contract, provider and request ID.
- Timeout and refund actions are permissionless and idempotent.
- The backend submits public winner proofs for automatic payout. It does not choose
  winners, custody player funds or override formula outcomes.
- SPIN does not execute market purchases, token sniping or price-driven trading.

## Testing and deployment

Use Foundry and Anvil for local unit, fuzz, invariant and integration testing.
Test formula boundaries, Dice fee changes, rollover, fee rounding, unique winners,
invalid Merkle-sum proofs, duplicate payouts, callbacks, timeouts and reentrancy.

Do not accept user funds until Dice's live addresses and bytecode are independently
verified, vault tests pass in CI and an independent audit has fixed critical findings.

## Sources

- [Dice integration guide](https://diceprotocol.world/docs/)
- [Dice security posture](https://diceprotocol.world/docs/security/)
- [Dice verification guide](https://diceprotocol.world/docs/verification/)
- [Dexch.art API](https://dexch.art/api-docs)
- [Solidity security considerations](https://docs.soliditylang.org/en/latest/security-considerations.html)
