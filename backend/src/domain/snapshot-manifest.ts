import {
  encodeAbiParameters,
  getAddress,
  isHex,
  keccak256,
  stringToHex,
  type Address,
  type Hex,
} from "viem";

import { buildHolderSnapshot, type SnapshotInput } from "./holder-snapshot.js";
import { filterToEligibleEoas, type EligibilityPolicyInput } from "./eligibility-policy.js";
import { MerkleSumTree, type MerkleSumRoot } from "./merkle-sum-tree.js";

const MANIFEST_DOMAIN = keccak256(stringToHex("SPIN_SNAPSHOT_MANIFEST_V1"));

export type SnapshotManifestInput = Readonly<{
  chainId: bigint;
  token: Address;
  snapshot: SnapshotInput;
  eligibility: EligibilityPolicyInput;
  startBlockHash: Hex;
  endBlockHash: Hex;
  roundConfigurationHash: Hex;
  exclusionListHash: Hex;
  cooldownExclusionListHash: Hex;
  calculationVersionHash: Hex;
}>;

export type SnapshotManifest = Readonly<{
  chainId: bigint;
  token: Address;
  startBlock: bigint;
  endBlock: bigint;
  startTimestamp: bigint;
  endTimestamp: bigint;
  startBlockHash: Hex;
  endBlockHash: Hex;
  roundConfigurationHash: Hex;
  exclusionListHash: Hex;
  cooldownExclusionListHash: Hex;
  calculationVersionHash: Hex;
  root: MerkleSumRoot;
  manifestHash: Hex;
}>;

export class SnapshotManifestValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "SnapshotManifestValidationError";
  }
}

export function createSnapshotManifest(input: SnapshotManifestInput): SnapshotManifest {
  validateManifestInput(input);

  const weightedSnapshot = buildHolderSnapshot(input.snapshot);
  const holderSnapshot = filterToEligibleEoas(weightedSnapshot, input.eligibility);

  if (holderSnapshot.holderCount === 0 || holderSnapshot.totalWeight === 0n) {
    throw new SnapshotManifestValidationError("snapshot must contain eligible holder weight");
  }

  const tree = new MerkleSumTree(holderSnapshot.holders);
  const token = getAddress(input.token);
  const { window } = input.snapshot;
  const manifest: Omit<SnapshotManifest, "manifestHash"> = {
    chainId: input.chainId,
    token,
    startBlock: window.startBlock,
    endBlock: window.endBlock,
    startTimestamp: window.startTimestamp,
    endTimestamp: window.endTimestamp,
    startBlockHash: input.startBlockHash,
    endBlockHash: input.endBlockHash,
    roundConfigurationHash: input.roundConfigurationHash,
    exclusionListHash: input.exclusionListHash,
    cooldownExclusionListHash: input.cooldownExclusionListHash,
    calculationVersionHash: input.calculationVersionHash,
    root: tree.root,
  };

  return {
    ...manifest,
    manifestHash: hashManifest(manifest),
  };
}

function validateManifestInput(input: SnapshotManifestInput): void {
  if (input.chainId <= 0n) {
    throw new SnapshotManifestValidationError("chainId must be positive");
  }

  getAddress(input.token);

  if (getAddress(input.eligibility.qualificationToken) !== getAddress(input.token)) {
    throw new SnapshotManifestValidationError("eligibility policy token must match snapshot token");
  }
  if (input.eligibility.cutoffBlockHash.toLowerCase() !== input.endBlockHash.toLowerCase()) {
    throw new SnapshotManifestValidationError("eligibility cutoff must match the snapshot end block");
  }
  if (input.eligibility.staticExclusionListHash.toLowerCase() !== input.exclusionListHash.toLowerCase()) {
    throw new SnapshotManifestValidationError("eligibility exclusions must match the round commitment");
  }
  if (input.eligibility.cooldownExclusionListHash.toLowerCase() !== input.cooldownExclusionListHash.toLowerCase()) {
    throw new SnapshotManifestValidationError("eligibility cooldown exclusions must match the manifest");
  }

  for (const value of [
    input.startBlockHash,
    input.endBlockHash,
    input.roundConfigurationHash,
    input.exclusionListHash,
    input.cooldownExclusionListHash,
    input.calculationVersionHash,
  ]) {
    if (!isHex(value, { strict: true }) || value.length !== 66) {
      throw new SnapshotManifestValidationError("manifest hashes must be bytes32 values");
    }
  }
}

function hashManifest(manifest: Omit<SnapshotManifest, "manifestHash">): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" },
        { type: "uint256" },
        { type: "address" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "uint256" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "bytes32" },
        { type: "uint256" },
        { type: "uint256" },
      ],
      [
        MANIFEST_DOMAIN,
        manifest.chainId,
        manifest.token,
        manifest.startBlock,
        manifest.endBlock,
        manifest.startTimestamp,
        manifest.endTimestamp,
        manifest.startBlockHash,
        manifest.endBlockHash,
        manifest.roundConfigurationHash,
        manifest.exclusionListHash,
        manifest.cooldownExclusionListHash,
        manifest.calculationVersionHash,
        manifest.root.hash,
        manifest.root.totalWeight,
        BigInt(manifest.root.leafCount),
      ],
    ),
  );
}
