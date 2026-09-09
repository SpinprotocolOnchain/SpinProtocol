import assert from "node:assert/strict";
import test from "node:test";

import {
  RoundSettlementValidationError,
  calculateRoundSettlement,
  type RoundSettlementInput,
} from "../../src/domain/round-settlement.js";

function input(overrides: Partial<RoundSettlementInput> = {}): RoundSettlementInput {
  return {
    trackedPot: 10_000n,
    randomnessFee: 100n,
    minimumPayout: 1_000n,
    maximumWinners: 10,
    eligibleHolderCount: 7,
    ...overrides,
  };
}

test("limits winners by the pot, project cap and eligible holder count", () => {
  const settlement = calculateRoundSettlement(input());
  assert.deepEqual(settlement, {
    shouldDraw: true,
    winnerCount: 7,
    randomnessFee: 100n,
    payoutPerWinner: 1_414n,
    rollover: 2n,
  });
});

test("rolls over the complete pot when a draw cannot meet one minimum payout", () => {
  const settlement = calculateRoundSettlement(input({ trackedPot: 1_099n }));
  assert.deepEqual(settlement, {
    shouldDraw: false,
    winnerCount: 0,
    randomnessFee: 0n,
    payoutPerWinner: 0n,
    rollover: 1_099n,
  });
});

test("never creates more winners than eligible holders", () => {
  const settlement = calculateRoundSettlement(input({ eligibleHolderCount: 2 }));
  assert.equal(settlement.shouldDraw, true);
  assert.equal(settlement.winnerCount, 2);
  assert.equal(settlement.payoutPerWinner, 4_950n);
  assert.equal(settlement.rollover, 0n);
});

test("handles a pot larger than JavaScript's safe integer range", () => {
  const settlement = calculateRoundSettlement(
    input({ trackedPot: 10n ** 40n, randomnessFee: 1n, maximumWinners: 10, eligibleHolderCount: 10 }),
  );

  assert.equal(settlement.shouldDraw, true);
  assert.equal(settlement.winnerCount, 10);
});

test("rejects invalid monetary inputs", () => {
  assert.throws(() => calculateRoundSettlement(input({ minimumPayout: 0n })), RoundSettlementValidationError);
  assert.throws(() => calculateRoundSettlement(input({ eligibleHolderCount: -1 })), RoundSettlementValidationError);
});
