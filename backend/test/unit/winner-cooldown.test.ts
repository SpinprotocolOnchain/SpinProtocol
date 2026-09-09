import assert from "node:assert/strict";
import test from "node:test";
import type { Address } from "viem";

import { deriveCooldownExclusions, hashCooldownExclusions, WINNER_COOLDOWN_ROUNDS } from "../../src/domain/winner-cooldown.js";

const alice = "0x1000000000000000000000000000000000000001" as Address;
const bob = "0x2000000000000000000000000000000000000002" as Address;

test("excludes only winners of the immediately preceding round", () => {
  assert.equal(WINNER_COOLDOWN_ROUNDS, 1n);
  assert.deepEqual(deriveCooldownExclusions(8n, [{ roundId: 7n, account: alice }, { roundId: 6n, account: bob }]), [alice]);
  assert.deepEqual(deriveCooldownExclusions(9n, [{ roundId: 7n, account: alice }]), []);
});

test("commits the exact cooldown list and rejects duplicate entries", () => {
  assert.notEqual(hashCooldownExclusions([]), hashCooldownExclusions([alice]));
  assert.throws(() => hashCooldownExclusions([alice, alice]));
});
