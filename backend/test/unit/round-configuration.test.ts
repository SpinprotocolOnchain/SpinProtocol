import assert from "node:assert/strict";
import test from "node:test";
import type { Address, Hex } from "viem";

import {
  RoundConfigurationValidationError,
  createRoundConfiguration,
  type RoundConfigurationInput,
  type RoundConfigurationLimits,
} from "../../src/domain/round-configuration.js";

const token = "0x1000000000000000000000000000000000000001" as Address;
const feeRouter = "0x2000000000000000000000000000000000000002" as Address;
const weth = "0x3000000000000000000000000000000000000003" as Address;
const bytes32 = (value: string): Hex => `0x${value.padStart(64, "0")}` as Hex;

const limits: RoundConfigurationLimits = { maximumWinners: 32 };

function input(overrides: Partial<RoundConfigurationInput> = {}): RoundConfigurationInput {
  return {
    chainId: 4_663n, roundId: 7n, qualificationToken: token, feeRouter, settlementAsset: weth,
    window: { startBlock: 1_000n, endBlock: 2_000n, startTimestamp: 10_000n, endTimestamp: 20_000n },
    finalityBlocks: 12n, reviewBlocks: 720n, minimumPayout: 1_000_000_000_000_000n, minimumEligibleWeight: 1n,
    maximumWinners: 10,
    exclusionListHash: bytes32("1"), calculationVersionHash: bytes32("2"), ...overrides,
  };
}

test("creates a stable pre-window configuration commitment", () => {
  const first = createRoundConfiguration(input(), limits);
  const second = createRoundConfiguration(input(), limits);
  assert.deepEqual(first, second);
  assert.equal(first.maximumWinners, 10);
});

test("changes the commitment when a payout rule changes", () => {
  const original = createRoundConfiguration(input(), limits);
  const changed = createRoundConfiguration(input({ minimumPayout: 2_000_000_000_000_000n }), limits);
  assert.notEqual(changed.configurationHash, original.configurationHash);
});

test("changes the commitment when the maximum winner limit changes", () => {
  const original = createRoundConfiguration(input(), limits);
  const changed = createRoundConfiguration(input({ maximumWinners: 2 }), limits);
  assert.notEqual(changed.configurationHash, original.configurationHash);
});

test("rejects unsafe round settings", () => {
  assert.throws(() => createRoundConfiguration(input({ maximumWinners: 33 }), limits), RoundConfigurationValidationError);
  assert.throws(() => createRoundConfiguration(input({ minimumPayout: 0n }), limits), RoundConfigurationValidationError);
  assert.throws(() => createRoundConfiguration(input({ minimumEligibleWeight: 0n }), limits), RoundConfigurationValidationError);
  assert.throws(() => createRoundConfiguration(input({ finalityBlocks: -1n }), limits), RoundConfigurationValidationError);
});
