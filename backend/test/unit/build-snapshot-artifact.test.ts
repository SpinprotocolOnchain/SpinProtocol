import assert from "node:assert/strict";
import test from "node:test";
import type { Address, Hex } from "viem";

import { buildSnapshotArtifact } from "../../src/application/build-snapshot-artifact.js";
import { hashStaticExclusionList } from "../../src/domain/eligibility-policy.js";
import { createRoundConfiguration } from "../../src/domain/round-configuration.js";

const alice = "0x1000000000000000000000000000000000000001" as Address;
const token = "0x2000000000000000000000000000000000000002" as Address;
const router = "0x3000000000000000000000000000000000000003" as Address;
const weth = "0x4000000000000000000000000000000000000004" as Address;
const zero = "0x0000000000000000000000000000000000000000" as Address;
const hash = (value: string): Hex => `0x${value.padStart(64, "0")}` as Hex;

test("builds a reproducible eligible snapshot from a read-only chain source", async () => {
  const configuration = createRoundConfiguration({
    chainId: 4_663n, roundId: 2n, qualificationToken: token, feeRouter: router, settlementAsset: weth,
    window: { startBlock: 10n, endBlock: 20n, startTimestamp: 100n, endTimestamp: 200n },
    finalityBlocks: 10n, reviewBlocks: 10n, minimumPayout: 1n, minimumEligibleWeight: 1n,
    maximumWinners: 1, exclusionListHash: hashStaticExclusionList([]), calculationVersionHash: hash("9"),
  }, { maximumWinners: 32 });
  const artifact = await buildSnapshotArtifact({
    readBlockNumber: async () => 30n,
    readTransfers: async (_token, from) => from < 10n
      ? [{ from: zero, to: alice, amount: 100n, blockNumber: 1n, logIndex: 0, timestamp: 10n }]
      : [],
    readBlockHash: async (block) => hash(block.toString()),
    readCode: async () => "0x",
    discoverPools: async () => [],
  }, { configuration, configurationLimits: { maximumWinners: 32 }, tokenDeploymentBlock: 1n, supportedFactories: [], staticExcludedAccounts: [], settledWinners: [] });

  assert.equal(artifact.eligibleHolderCount, 1);
  assert.equal(artifact.manifest.root.totalWeight, 10_000n);
});

test("refuses to build a root until the committed finality depth has passed", async () => {
  const configuration = createRoundConfiguration({
    chainId: 4_663n, roundId: 2n, qualificationToken: token, feeRouter: router, settlementAsset: weth,
    window: { startBlock: 10n, endBlock: 20n, startTimestamp: 100n, endTimestamp: 200n },
    finalityBlocks: 10n, reviewBlocks: 10n, minimumPayout: 1n, minimumEligibleWeight: 1n,
    maximumWinners: 1, exclusionListHash: hashStaticExclusionList([]), calculationVersionHash: hash("9"),
  }, { maximumWinners: 32 });

  await assert.rejects(() => buildSnapshotArtifact({
    readBlockNumber: async () => 29n,
    readTransfers: async () => [],
    readBlockHash: async (block) => hash(block.toString()),
    readCode: async () => "0x",
    discoverPools: async () => [],
  }, { configuration, configurationLimits: { maximumWinners: 32 }, tokenDeploymentBlock: 1n, supportedFactories: [], staticExcludedAccounts: [], settledWinners: [] }), /snapshot cutoff is not final/);
});
