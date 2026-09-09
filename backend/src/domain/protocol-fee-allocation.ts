const BPS_DENOMINATOR = 10_000n;

/**
 * Immutable SPIN v1 fee policy. The project jackpot receives the remainder so
 * every rounding wei stays with the project rather than an administrator.
 */
export const SPIN_FEE_POLICY = Object.freeze({
  projectJackpotBps: 9_750,
  creatorTreasuryBps: 100,
  spinHolderJackpotBps: 100,
  buybackReserveBps: 50,
});

export type ProtocolFeeAllocation = Readonly<{
  grossDeposit: bigint;
  projectJackpot: bigint;
  creatorTreasury: bigint;
  spinHolderJackpot: bigint;
  buybackReserve: bigint;
}>;

export function allocateProtocolFee(grossDeposit: bigint): ProtocolFeeAllocation {
  if (grossDeposit < 0n) throw new Error("grossDeposit cannot be negative");

  const creatorTreasury = (grossDeposit * BigInt(SPIN_FEE_POLICY.creatorTreasuryBps)) / BPS_DENOMINATOR;
  const spinHolderJackpot = (grossDeposit * BigInt(SPIN_FEE_POLICY.spinHolderJackpotBps)) / BPS_DENOMINATOR;
  const buybackReserve = (grossDeposit * BigInt(SPIN_FEE_POLICY.buybackReserveBps)) / BPS_DENOMINATOR;
  const projectJackpot = grossDeposit - creatorTreasury - spinHolderJackpot - buybackReserve;

  return { grossDeposit, projectJackpot, creatorTreasury, spinHolderJackpot, buybackReserve };
}
