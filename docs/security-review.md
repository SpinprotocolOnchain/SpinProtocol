# PRD review and security decisions

Reviewed: 2026-09-08. This is architecture review, not a smart-contract audit.

## Kept and corrected

| PRD requirement | SPIN design |
| --- | --- |
| Protocol fee allocation | Every accepted WETH deposit uses the immutable 97.5% / 1% / 1% / 0.5% allocation before a project pot is credited. |
| Dynamic payout count | `min(maximumWinners, pot / minimumPayout, holderCount)` determines it on-chain. |
| Insufficient-pot rollover | The round stays open without Dice or a protocol-fee transfer. |
| Proportional winner odds | Merkle-sum proofs select by time-weighted holder percentage. |
| Multi-winner jackpot | Weighted selection without replacement creates unique winners. |
| Anti-dust behavior | `minimumPayout` blocks tiny payouts; division remainder carries forward. |

## Removed

| PRD item | Reason |
| --- | --- |
| Own-token “pump” and green-candle objective | It is market manipulation, not a safe jackpot mechanism. |
| Automated external-token sniping | It exposes jackpot funds to MEV, hostile tokens and stale data. |
| `isWidgetActive` fund condition | A caller can lie about an off-chain UI state. |
| USD payout brackets | They require a trusted price oracle; 0.3 WETH is not a fixed USD value. |
| Raw `balanceOf` settlement | Direct transfers could alter a draw. |
| Unbounded holder loops | Large participation can exceed the block gas limit. |

## Completed foundations

- The backend rejects a snapshot if the static exclusion list, event-derived
  cooldown list, historical account-code evidence or supported-pool evidence
  differs from its committed value.
- The Robinhood RPC reader validates chain ID and reads transfer and pool history in
  configurable bounded ranges; changing RPC provider cannot change the calculation.
- The Dice consumer is isolated from jackpot funds. Only its vault may request or
  refund randomness; only the configured Dice oracle and provider may resolve it.
- Foundry compiles the pinned Solidity version and exercises these Dice access
  boundaries locally without a network or gas fees.
- The WETH intake vault accepts deposits only from its immutable fee router and
  verifies the token balance delta before it credits the jackpot pot. It has no
  administrative withdrawal function.
- A Dice request reserves its exact oracle cost and the entire calculated winner
  budget before requesting randomness. New deposits therefore cannot be paid into
  an already requested draw. Each successful payout can only transfer the fixed,
  reserved amount directly to the cryptographically selected wallet.
- Factory deployment atomically wires the vault to its settlement controller;
  the fee router cannot select or replace that controller. A separate contract
  approver, normally a multisig or timelock, must finalize each external-token
  snapshot after the public review period.
- The contract verifies a Merkle-sum proof for every winner, derives a uniformly
  distributed weighted position with rejection sampling, and removes that winner's
  weight before the next selection. A winner cannot be paid twice in one round.
- OpenZeppelin Contracts is pinned to `v5.6.1` at commit
  `5fd1781b1454fd1ef8e722282f86f9293cacf256`; later work uses its reviewed
  token-transfer and access-control primitives instead of local replacements.

## Required before vault deployment

1. Confirm the WETH fee-router interface and deposit authorization model, then
   verify the factory deployment manifest, factory bytecode and child addresses
   before enabling deposits.
2. Define the Merkle-sum leaf, including wallet, time-weighted balance and tree
   position, plus the qualification window and exclusion rules.
   The window's start/end blocks, exclusion-list hash and calculation-version hash
   must be committed on-chain before the window starts.
   Decide whether the product requires checkpoint token mode; only that mode may be
   promoted as fully provably fair.
3. Select the maximum-winner constant using Foundry gas tests for weighted proof
   verification and tree updates.
4. Run an end-to-end Dice callback and direct-WETH-payout test against the exact
   deployed Dice ABI, including non-zero oracle fee and refund behaviour.
5. Validate the round-specific fee-router integration: deposits close after the
   inclusive qualification end block. Confirm operational handling of rejected
   late deposits, rollover destinations and retries blocked by increased Dice fees.
6. Verify the snapshot approver is a production multisig or timelock with a
   documented review procedure; external-token eligibility is administered mode.
7. Verify Dice mainnet/testnet ABI and deployed bytecode against the reviewed
   version immediately before configuration.
8. Write the threat model, test the implementation and obtain an independent audit.
