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
  readChainId(): Promise<bigint>;
  readBlockNumber(): Promise<bigint>;
  readTransfers(token: Address, fromBlock: bigint, toBlock: bigint): Promise<readonly TokenTransfer[]>;
  readBlockHash(blockNumber: bigint): Promise<Hex>;
  readCode(account: Address, blockNumber: bigint, blockHash: Hex): Promise<Hex>;
  readSettledWinners(
    settlementController: Address,
    roundId: bigint,
    fromBlock: bigint,
    toBlock: bigint,
  ): Promise<readonly SettledWinner[]>;
  discoverPools(token: Address, fromBlock: bigint, toBlock: bigint): Promise<readonly DiscoveredPool[]>;
}>;

export type SnapshotArtifactInput = Readonly<{
  configuration: RoundConfiguration;
  configurationLimits: RoundConfigurationLimits;
  tokenDeploymentBlock: bigint;
  supportedFactories: readonly SupportedPoolFactory[];
  staticExcludedAccounts: readonly Address[];
  settlementController: Address;
  settlementControllerDeploymentBlock: bigint;
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
  if (
    input.settlementControllerDeploymentBlock < 0n
      || input.settlementControllerDeploymentBlock > configuration.window.endBlock
  ) {
    throw new Error("settlement controller deployment block is outside the round history");
  }

  if (await reader.readChainId() !== configuration.chainId) {
    throw new Error("snapshot reader chain ID does not match the round configuration");
  }

  const requiredFinalizedBlock = configuration.window.endBlock + configuration.finalityBlocks;
  const headBlock = await reader.readBlockNumber();

  if (headBlock < requiredFinalizedBlock) {
    throw new Error(`snapshot cutoff is not final: need block ${requiredFinalizedBlock}, head is ${headBlock}`);
  }

  const startBlockHash = await reader.readBlockHash(configuration.window.startBlock);

  const endBlockHash = await reader.readBlockHash(configuration.window.endBlock);

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

  const [discoveredPools, accountCode] = await Promise.all([
    reader.discoverPools(configuration.qualificationToken, input.tokenDeploymentBlock, configuration.window.endBlock),
    Promise.all(weighted.holders.map(async ({ account }) => ({ account, blockHash: endBlockHash, code: await reader.readCode(account, configuration.window.endBlock, endBlockHash) }))),
  ]);

  const priorRoundWinners = configuration.roundId === 0n
    ? []
    : await reader.readSettledWinners(
      input.settlementController,
      configuration.roundId - 1n,
      input.settlementControllerDeploymentBlock,
      configuration.window.endBlock,
    );
  const cooldownExcludedAccounts = deriveCooldownExclusions(configuration.roundId, priorRoundWinners);

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
    startBlockHash,
    endBlockHash,
    roundConfigurationHash: configuration.configurationHash,
    exclusionListHash: configuration.exclusionListHash,
    cooldownExclusionListHash,
    calculationVersionHash: configuration.calculationVersionHash,
  });
  if (await reader.readBlockHash(configuration.window.startBlock) !== startBlockHash
    || await reader.readBlockHash(configuration.window.endBlock) !== endBlockHash
    || await reader.readChainId() !== configuration.chainId) {
    throw new Error("chain changed while building the snapshot; discard and retry");
  }
  return { manifest, eligibleHolderCount: eligible.holderCount, cooldownExcludedAccounts, discoveredPools, accountCode };
}
