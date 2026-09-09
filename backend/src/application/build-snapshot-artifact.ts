import type { Address, Hex } from "viem";

import {
  filterToEligibleEoas,
  hashStaticExclusionList,
  type AccountCodeEvidence,
  type DiscoveredPool,
  type SupportedPoolFactory,
} from "../domain/eligibility-policy.js";
import { buildHolderSnapshot, type TokenTransfer } from "../domain/holder-snapshot.js";
import { createRoundConfiguration, type RoundConfiguration, type RoundConfigurationLimits } from "../domain/round-configuration.js";
import { createIndexedSnapshotInput } from "../domain/snapshot-indexer.js";
import { createSnapshotManifest, type SnapshotManifest } from "../domain/snapshot-manifest.js";
import { deriveCooldownExclusions, hashCooldownExclusions, type SettledWinner } from "../domain/winner-cooldown.js";

export type SnapshotChainReader = Readonly<{
  readBlockNumber(): Promise<bigint>;
  readTransfers(token: Address, fromBlock: bigint, toBlock: bigint): Promise<readonly TokenTransfer[]>;
  readBlockHash(blockNumber: bigint): Promise<Hex>;
  readCode(account: Address, blockNumber: bigint): Promise<Hex>;
  discoverPools(token: Address, fromBlock: bigint, toBlock: bigint): Promise<readonly DiscoveredPool[]>;
}>;

export type SnapshotArtifactInput = Readonly<{
  configuration: RoundConfiguration;
  configurationLimits: RoundConfigurationLimits;
  tokenDeploymentBlock: bigint;
  supportedFactories: readonly SupportedPoolFactory[];
  staticExcludedAccounts: readonly Address[];
  settledWinners: readonly SettledWinner[];
}>;

export type SnapshotArtifact = Readonly<{
  manifest: SnapshotManifest;
  eligibleHolderCount: number;
  cooldownExcludedAccounts: readonly Address[];
  discoveredPools: readonly DiscoveredPool[];
  accountCode: readonly AccountCodeEvidence[];
}>;

/** Builds a root only from data read through the supplied, auditable chain reader. */
export async function buildSnapshotArtifact(
  reader: SnapshotChainReader,
  input: SnapshotArtifactInput,
): Promise<SnapshotArtifact> {
  const configuration = createRoundConfiguration(input.configuration, input.configurationLimits);
  if (configuration.configurationHash !== input.configuration.configurationHash) {
    throw new Error("round configuration hash does not match its contents");
  }
  if (configuration.exclusionListHash !== hashStaticExclusionList(input.staticExcludedAccounts)) {
    throw new Error("static exclusions do not match the locked round configuration");
  }
  if (input.tokenDeploymentBlock < 0n || input.tokenDeploymentBlock >= configuration.window.startBlock) {
    throw new Error("token deployment block must be before the qualification window");
  }
  const requiredFinalizedBlock = configuration.window.endBlock + configuration.finalityBlocks;
  const headBlock = await reader.readBlockNumber();
  if (headBlock < requiredFinalizedBlock) {
    throw new Error(`snapshot cutoff is not final: need block ${requiredFinalizedBlock}, head is ${headBlock}`);
  }

  const beforeWindow = await reader.readTransfers(
    configuration.qualificationToken,
    input.tokenDeploymentBlock,
    configuration.window.startBlock - 1n,
  );
  const windowTransfers = await reader.readTransfers(
    configuration.qualificationToken,
    configuration.window.startBlock,
    configuration.window.endBlock,
  );
  const snapshot = createIndexedSnapshotInput({
    transfersBeforeWindow: beforeWindow,
    snapshot: { window: configuration.window, transfers: windowTransfers, minimumWeight: configuration.minimumEligibleWeight },
  });
  const weighted = buildHolderSnapshot(snapshot);
  const endBlockHash = await reader.readBlockHash(configuration.window.endBlock);
  const [discoveredPools, accountCode] = await Promise.all([
    reader.discoverPools(configuration.qualificationToken, input.tokenDeploymentBlock, configuration.window.endBlock),
    Promise.all(weighted.holders.map(async ({ account }) => ({ account, blockHash: endBlockHash, code: await reader.readCode(account, configuration.window.endBlock) }))),
  ]);
  const cooldownExcludedAccounts = deriveCooldownExclusions(configuration.roundId, input.settledWinners);
  const cooldownExclusionListHash = hashCooldownExclusions(cooldownExcludedAccounts);
  const eligibility = {
    qualificationToken: configuration.qualificationToken,
    cutoffBlockHash: endBlockHash,
    staticExcludedAccounts: input.staticExcludedAccounts,
    staticExclusionListHash: configuration.exclusionListHash,
    cooldownExcludedAccounts,
    cooldownExclusionListHash,
    supportedFactories: input.supportedFactories,
    discoveredPools,
    accountCode,
  };
  const eligible = filterToEligibleEoas(weighted, eligibility);
  const manifest = createSnapshotManifest({
    chainId: configuration.chainId,
    token: configuration.qualificationToken,
    snapshot,
    eligibility,
    startBlockHash: await reader.readBlockHash(configuration.window.startBlock),
    endBlockHash,
    roundConfigurationHash: configuration.configurationHash,
    exclusionListHash: configuration.exclusionListHash,
    cooldownExclusionListHash,
    calculationVersionHash: configuration.calculationVersionHash,
  });
  return { manifest, eligibleHolderCount: eligible.holderCount, cooldownExcludedAccounts, discoveredPools, accountCode };
}
