import assert from "node:assert/strict";
import test from "node:test";
import type { Address, Hex } from "viem";

import {
  EligibilityPolicyValidationError,
  filterToEligibleEoas,
  hashStaticExclusionList,
  type EligibilityPolicyInput,
} from "../../src/domain/eligibility-policy.js";
import { hashCooldownExclusions } from "../../src/domain/winner-cooldown.js";

const alice = "0x1000000000000000000000000000000000000001" as Address;
const bob = "0x2000000000000000000000000000000000000002" as Address;
const pool = "0x3000000000000000000000000000000000000003" as Address;
const token = "0x4000000000000000000000000000000000000004" as Address;
const other = "0x5000000000000000000000000000000000000005" as Address;
const factory = "0x6000000000000000000000000000000000000006" as Address;
const hash = `0x${"1".padStart(64, "0")}` as Hex;

function input(overrides: Partial<EligibilityPolicyInput> = {}): EligibilityPolicyInput {
  return {
    qualificationToken: token,
    cutoffBlockHash: hash,
    staticExcludedAccounts: [],
    staticExclusionListHash: hashStaticExclusionList([]),
    cooldownExcludedAccounts: [],
    cooldownExclusionListHash: hashCooldownExclusions([]),
    supportedFactories: [{ adapterId: "v2", factory }],
    discoveredPools: [{ adapterId: "v2", factory, pool, token0: token, token1: other }],
    accountCode: [
      { account: alice, blockHash: hash, code: "0x" },
      { account: bob, blockHash: hash, code: "0x1234" },
      { account: pool, blockHash: hash, code: "0x1234" },
    ],
    ...overrides,
  };
}

test("keeps only EOAs and excludes a factory-verified LP pool", () => {
  const result = filterToEligibleEoas(
    { holders: [{ account: alice, weight: 60n }, { account: bob, weight: 30n }, { account: pool, weight: 10n }], holderCount: 3, totalWeight: 100n },
    input(),
  );
  assert.deepEqual(result, { holders: [{ account: alice, weight: 60n }], holderCount: 1, totalWeight: 60n });
});

test("refuses a root candidate when its historical code proof is missing", () => {
  assert.throws(
    () => filterToEligibleEoas({ holders: [{ account: alice, weight: 1n }], holderCount: 1, totalWeight: 1n }, input({ accountCode: [] })),
    EligibilityPolicyValidationError,
  );
});

test("refuses a pool claimed from an unknown factory", () => {
  assert.throws(
    () => filterToEligibleEoas({ holders: [], holderCount: 0, totalWeight: 0n }, input({ discoveredPools: [{ adapterId: "unknown", factory, pool, token0: token, token1: other }] })),
    EligibilityPolicyValidationError,
  );
});

test("excludes a committed treasury address", () => {
  const result = filterToEligibleEoas(
    { holders: [{ account: alice, weight: 1n }], holderCount: 1, totalWeight: 1n },
    input({ staticExcludedAccounts: [alice], staticExclusionListHash: hashStaticExclusionList([alice]) }),
  );
  assert.deepEqual(result, { holders: [], holderCount: 0, totalWeight: 0n });
});

test("refuses a cooldown list whose hash was altered", () => {
  assert.throws(
    () => filterToEligibleEoas({ holders: [{ account: alice, weight: 1n }], holderCount: 1, totalWeight: 1n }, input({ cooldownExcludedAccounts: [alice] })),
    EligibilityPolicyValidationError,
  );
});
