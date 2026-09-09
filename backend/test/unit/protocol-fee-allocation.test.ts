import assert from "node:assert/strict";
import test from "node:test";

import { SPIN_FEE_POLICY, allocateProtocolFee } from "../../src/domain/protocol-fee-allocation.js";

test("allocates every wei from a deposit without changing the fixed policy", () => {
  assert.deepEqual(SPIN_FEE_POLICY, {
    projectJackpotBps: 9_750,
    creatorTreasuryBps: 100,
    spinHolderJackpotBps: 100,
    buybackReserveBps: 50,
  });
  const allocation = allocateProtocolFee(10_000n);
  assert.deepEqual(allocation, {
    grossDeposit: 10_000n,
    projectJackpot: 9_750n,
    creatorTreasury: 100n,
    spinHolderJackpot: 100n,
    buybackReserve: 50n,
  });
});

test("leaves rounding dust in the project jackpot", () => {
  const allocation = allocateProtocolFee(101n);
  assert.equal(allocation.projectJackpot + allocation.creatorTreasury + allocation.spinHolderJackpot + allocation.buybackReserve, 101n);
  assert.deepEqual(allocation, {
    grossDeposit: 101n,
    projectJackpot: 99n,
    creatorTreasury: 1n,
    spinHolderJackpot: 1n,
    buybackReserve: 0n,
  });
});
