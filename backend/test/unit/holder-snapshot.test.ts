import assert from "node:assert/strict";
import test from "node:test";
import { zeroAddress, type Address } from "viem";

import {
  SnapshotValidationError,
  buildHolderSnapshot,
  type SnapshotInput,
} from "../../src/domain/holder-snapshot.js";

const alice = "0x1000000000000000000000000000000000000001" as Address;
const bob = "0x2000000000000000000000000000000000000002" as Address;
const carol = "0x3000000000000000000000000000000000000003" as Address;

function input(overrides: Partial<SnapshotInput> = {}): SnapshotInput {
  return {
    window: {
      startBlock: 100n,
      endBlock: 200n,
      startTimestamp: 1_000n,
      endTimestamp: 1_100n,
    },
    initialBalances: [],
    transfers: [],
    ...overrides,
  };
}

test("weights balances by the time each wallet held them", () => {
  const snapshot = buildHolderSnapshot(
    input({
      initialBalances: [
        { account: alice, balance: 50n },
        { account: bob, balance: 50n },
      ],
      transfers: [
        {
          from: bob,
          to: carol,
          amount: 50n,
          blockNumber: 150n,
          logIndex: 0,
          timestamp: 1_050n,
        },
      ],
    }),
  );

  assert.deepEqual(snapshot.holders, [
    { account: alice, weight: 5_000n },
    { account: bob, weight: 2_500n },
    { account: carol, weight: 2_500n },
  ]);
  assert.equal(snapshot.totalWeight, 10_000n);
});

test("supports minting and burning without making the zero address eligible", () => {
  const snapshot = buildHolderSnapshot(
    input({
      transfers: [
        {
          from: zeroAddress,
          to: alice,
          amount: 100n,
          blockNumber: 120n,
          logIndex: 0,
          timestamp: 1_020n,
        },
        {
          from: alice,
          to: zeroAddress,
          amount: 40n,
          blockNumber: 170n,
          logIndex: 0,
          timestamp: 1_070n,
        },
      ],
    }),
  );

  assert.deepEqual(snapshot.holders, [{ account: alice, weight: 6_800n }]);
});

test("rejects a transfer that cannot be reconciled with tracked balances", () => {
  assert.throws(
    () =>
      buildHolderSnapshot(
        input({
          transfers: [
            {
              from: alice,
              to: bob,
              amount: 1n,
              blockNumber: 120n,
              logIndex: 0,
              timestamp: 1_020n,
            },
          ],
        }),
      ),
    SnapshotValidationError,
  );
});

test("rejects logs that are not in canonical order", () => {
  assert.throws(
    () =>
      buildHolderSnapshot(
        input({
          initialBalances: [{ account: alice, balance: 2n }],
          transfers: [
            {
              from: alice,
              to: bob,
              amount: 1n,
              blockNumber: 130n,
              logIndex: 1,
              timestamp: 1_030n,
            },
            {
              from: alice,
              to: carol,
              amount: 1n,
              blockNumber: 130n,
              logIndex: 0,
              timestamp: 1_030n,
            },
          ],
        }),
      ),
    SnapshotValidationError,
  );
});
