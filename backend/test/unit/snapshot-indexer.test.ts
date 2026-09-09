import assert from "node:assert/strict";
import test from "node:test";
import { zeroAddress, type Address } from "viem";

import {
  SnapshotIndexerValidationError,
  createIndexedSnapshotInput,
  deriveBalancesBeforeWindow,
} from "../../src/domain/snapshot-indexer.js";

const alice = "0x1000000000000000000000000000000000000001" as Address;
const bob = "0x2000000000000000000000000000000000000002" as Address;

const mint = {
  from: zeroAddress,
  to: alice,
  amount: 100n,
  blockNumber: 10n,
  logIndex: 0,
  timestamp: 100n,
};

test("derives balances before the start block without double-applying its logs", () => {
  const snapshot = createIndexedSnapshotInput({
    transfersBeforeWindow: [mint],
    snapshot: {
      window: { startBlock: 20n, endBlock: 30n, startTimestamp: 200n, endTimestamp: 300n },
      transfers: [{ from: alice, to: bob, amount: 20n, blockNumber: 20n, logIndex: 0, timestamp: 200n }],
    },
  });

  assert.deepEqual(snapshot.initialBalances, [{ account: alice, balance: 100n }]);
  assert.equal(snapshot.transfers.length, 1);
});

test("rejects history that overlaps the qualification window", () => {
  assert.throws(
    () => deriveBalancesBeforeWindow([{ ...mint, blockNumber: 20n }], 20n),
    SnapshotIndexerValidationError,
  );
});

test("rejects history that cannot be reconciled from mint and transfer events", () => {
  assert.throws(
    () => deriveBalancesBeforeWindow([{ ...mint, from: alice, to: bob }], 20n),
    SnapshotIndexerValidationError,
  );
});
