import assert from "node:assert/strict";
import test from "node:test";

import {
  ROBINHOOD_CHAIN_ID,
  RobinhoodRpcValidationError,
  assertRobinhoodChain,
  createRobinhoodPublicClient,
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
