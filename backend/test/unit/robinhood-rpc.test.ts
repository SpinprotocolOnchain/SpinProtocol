import assert from "node:assert/strict";
import test from "node:test";

import {
  ROBINHOOD_CHAIN_ID,
  RobinhoodRpcValidationError,
  assertRobinhoodChain,
  createRobinhoodPublicClient,
  readSettlementWinners,
  readTokenTransfers,
} from "../../src/adapters/chains/evm/robinhood-rpc.js";

test("rejects an RPC endpoint on the wrong chain", async () => {
  await assert.rejects(
    () => assertRobinhoodChain({ getChainId: async () => 1 } as never),
    RobinhoodRpcValidationError,
  );
});

test("accepts the configured Robinhood Chain ID", async () => {
  await assert.doesNotReject(() => assertRobinhoodChain({ getChainId: async () => ROBINHOOD_CHAIN_ID } as never));
});

test("requires HTTPS for production RPC endpoints", () => {
  assert.throws(() => createRobinhoodPublicClient({ rpcUrl: "http://rpc.example" }), RobinhoodRpcValidationError);
});

test("rejects HTTP endpoints disguised as local addresses", () => {
  for (const rpcUrl of ["http://127.0.0.1.evil.example", "http://127.0.0.1@evil.example"]) {
    assert.throws(() => createRobinhoodPublicClient({ rpcUrl }), RobinhoodRpcValidationError);
  }
});

test("rejects transfer logs from a different block hash", async () => {
  const hashA = `0x${"a".repeat(64)}`;
  const hashB = `0x${"b".repeat(64)}`;
  const client = {
    getLogs: async () => [{ blockNumber: 10n, blockHash: hashA, logIndex: 0, removed: false,
      args: { from: "0x0000000000000000000000000000000000000000", to: "0x1000000000000000000000000000000000000001", value: 1n } }],
    getBlock: async () => ({ number: 10n, hash: hashB, timestamp: 100n }),
  };
  await assert.rejects(() => readTokenTransfers(client as never, {
    token: "0x2000000000000000000000000000000000000002", fromBlock: 10n, toBlock: 10n,
  }), RobinhoodRpcValidationError);
});

test("reads cooldown winners only from the configured controller and canonical blocks", async () => {
  const hash = `0x${"c".repeat(64)}`;
  const controller = "0x3000000000000000000000000000000000000003";
  const winner = "0x4000000000000000000000000000000000000004";
  const client = {
    getLogs: async (query: { address: string; args: { roundId: bigint } }) => {
      assert.equal(query.address, controller);
      assert.equal(query.args.roundId, 7n);
      return [{ blockNumber: 20n, blockHash: hash, removed: false,
        args: { winner } }];
    },
    getBlock: async () => ({ number: 20n, hash, timestamp: 100n }),
  };
  const winners = await readSettlementWinners(client as never, {
    settlementController: controller,
    roundId: 7n,
    fromBlock: 10n,
    toBlock: 20n,
  });
  assert.deepEqual(winners, [{ roundId: 7n, account: winner }]);
});

test("rejects winner events from a reorged block", async () => {
  const client = {
    getLogs: async () => [{ blockNumber: 20n, blockHash: `0x${"c".repeat(64)}`, removed: false,
      args: { winner: "0x4000000000000000000000000000000000000004" } }],
    getBlock: async () => ({ number: 20n, hash: `0x${"d".repeat(64)}`, timestamp: 100n }),
  };
  await assert.rejects(() => readSettlementWinners(client as never, {
    settlementController: "0x3000000000000000000000000000000000000003",
    roundId: 7n,
    fromBlock: 10n,
    toBlock: 20n,
  }), RobinhoodRpcValidationError);
});
