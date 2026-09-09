const BPS_DENOMINATOR = 10_000n;

export type RoundSettlementInput = Readonly<{
  /** WETH deposits attributed to this round; never use an arbitrary vault balance. */
  trackedPot: bigint;
  /** Exact price quoted by Dice immediately before requesting randomness. */
  randomnessFee: bigint;
  minimumPayout: bigint;
  maximumWinners: number;
  eligibleHolderCount: number;
}>;

export type DeferredSettlement = Readonly<{
  shouldDraw: false;
  winnerCount: 0;
  randomnessFee: 0n;
  payoutPerWinner: 0n;
  rollover: bigint;
}>;

export type ExecutableSettlement = Readonly<{
  shouldDraw: true;
  winnerCount: number;
  randomnessFee: bigint;
  payoutPerWinner: bigint;
  /** Dust from integer division remains in the next round. */
  rollover: bigint;
}>;

export type RoundSettlement = DeferredSettlement | ExecutableSettlement;

export class RoundSettlementValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "RoundSettlementValidationError";
  }
}

/**
 * Decides whether the current tracked pot can fund a draw. A failed calculation
 * spends nothing: no Dice request and the whole pot rolls over. Protocol fees
 * were already allocated when the WETH deposit entered the project pot.
 */
export function calculateRoundSettlement(input: RoundSettlementInput): RoundSettlement {
  validate(input);

  if (input.trackedPot <= input.randomnessFee || input.eligibleHolderCount === 0) {
    return deferred(input.trackedPot);
  }

  const afterRandomness = input.trackedPot - input.randomnessFee;
  const distributable = afterRandomness;
  const affordableWinnerCount = distributable / input.minimumPayout;
  const configuredWinnerCount = Math.min(input.maximumWinners, input.eligibleHolderCount);
  // Only convert after proving the bigint fits below a safe integer cap. A jackpot
  // can be much larger than Number.MAX_SAFE_INTEGER, while winner counts cannot.
  const winnerCount =
    affordableWinnerCount >= BigInt(configuredWinnerCount)
      ? configuredWinnerCount
      : Number(affordableWinnerCount);

  if (winnerCount === 0) return deferred(input.trackedPot);

  const payoutPerWinner = distributable / BigInt(winnerCount);
  const rollover = distributable % BigInt(winnerCount);

  return {
    shouldDraw: true,
    winnerCount,
    randomnessFee: input.randomnessFee,
    payoutPerWinner,
    rollover,
  };
}

function deferred(trackedPot: bigint): DeferredSettlement {
  return {
    shouldDraw: false,
    winnerCount: 0,
    randomnessFee: 0n,
    payoutPerWinner: 0n,
    rollover: trackedPot,
  };
}

function validate(input: RoundSettlementInput): void {
  for (const [name, value] of [
    ["trackedPot", input.trackedPot],
    ["randomnessFee", input.randomnessFee],
    ["minimumPayout", input.minimumPayout],
  ] as const) {
    if (value < 0n) throw new RoundSettlementValidationError(`${name} cannot be negative`);
  }

  if (input.minimumPayout === 0n) {
    throw new RoundSettlementValidationError("minimumPayout must be positive");
  }

  for (const [name, value] of [
    ["maximumWinners", input.maximumWinners],
    ["eligibleHolderCount", input.eligibleHolderCount],
  ] as const) {
    if (!Number.isSafeInteger(value)) {
      throw new RoundSettlementValidationError(`${name} must be a safe integer`);
    }
  }

  if (input.maximumWinners < 1) {
    throw new RoundSettlementValidationError("maximumWinners must be positive");
  }
  if (input.eligibleHolderCount < 0) {
    throw new RoundSettlementValidationError("eligibleHolderCount cannot be negative");
  }
}
