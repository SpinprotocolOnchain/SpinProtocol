import {
  encodeAbiParameters,
  getAddress,
  keccak256,
  stringToHex,
  type Address,
  type Hex,
} from "viem";

import type { HolderWeight } from "./holder-snapshot.js";

const LEAF_DOMAIN = keccak256(stringToHex("SPIN_MERKLE_SUM_LEAF_V1"));
const NODE_DOMAIN = keccak256(stringToHex("SPIN_MERKLE_SUM_NODE_V1"));
const ZERO_HASH = keccak256(stringToHex("SPIN_MERKLE_SUM_ZERO_V1"));

export type MerkleSumRoot = Readonly<{
  hash: Hex;
  totalWeight: bigint;
  leafCount: number;
}>;

export type MerkleSumSibling = Readonly<{
  hash: Hex;
  weight: bigint;
}>;

export type MerkleSumProof = Readonly<{
  index: number;
  account: Address;
  weight: bigint;
  siblings: readonly MerkleSumSibling[];
}>;

type MerkleSumNode = Readonly<{
  hash: Hex;
  weight: bigint;
}>;

export class MerkleSumValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "MerkleSumValidationError";
  }
}

export class MerkleSumTree {
  public readonly root: MerkleSumRoot;
  private readonly levels: readonly (readonly MerkleSumNode[])[];
  private readonly leaves: readonly HolderWeight[];

  public constructor(
    holders: readonly HolderWeight[],
    options: Readonly<{ allowZeroWeights?: boolean }> = {},
  ) {
    validateHolders(holders, options.allowZeroWeights ?? false);
    this.leaves = holders.map((holder) => ({
      account: getAddress(holder.account),
      weight: holder.weight,
    }));
    this.levels = buildLevels(this.leaves);

    const rootNode = this.levels.at(-1)?.[0];

    if (rootNode === undefined) {
      throw new MerkleSumValidationError("a Merkle-sum tree requires at least one holder");
    }

    this.root = {
      hash: rootNode.hash,
      totalWeight: rootNode.weight,
      leafCount: this.leaves.length,
    };
  }

  public getProof(index: number): MerkleSumProof {
    if (!Number.isSafeInteger(index) || index < 0 || index >= this.leaves.length) {
      throw new MerkleSumValidationError("proof index is outside the holder list");
    }

    const holder = this.leaves[index];

    if (holder === undefined) {
      throw new MerkleSumValidationError("holder is missing at proof index");
    }

    const siblings: MerkleSumSibling[] = [];
    let nodeIndex = index;

    for (let levelIndex = 0; levelIndex < this.levels.length - 1; levelIndex += 1) {
      const level = this.levels[levelIndex];

      if (level === undefined) {
        throw new MerkleSumValidationError("Merkle-sum tree level is missing");
      }

      const siblingIndex = nodeIndex ^ 1;
      const sibling = level[siblingIndex];

      if (sibling === undefined) {
        throw new MerkleSumValidationError("Merkle-sum tree sibling is missing");
      }

      siblings.push(sibling);
      nodeIndex = Math.floor(nodeIndex / 2);
    }

    return {
      index,
      account: holder.account,
      weight: holder.weight,
      siblings,
    };
  }

  public withoutHolder(index: number): MerkleSumTree {
    const holder = this.leaves[index];

    if (holder === undefined || holder.weight <= 0n) {
      throw new MerkleSumValidationError("only an active holder can be removed");
    }

    const remainingHolders = this.leaves.map((currentHolder, currentIndex) => ({
      account: currentHolder.account,
      weight: currentIndex === index ? 0n : currentHolder.weight,
    }));

    return new MerkleSumTree(remainingHolders, { allowZeroWeights: true });
  }
}

export function verifiesWeightedSelection(
  root: MerkleSumRoot,
  randomPosition: bigint,
  proof: MerkleSumProof,
): boolean {
  if (randomPosition < 0n || randomPosition >= root.totalWeight || proof.weight <= 0n) {
    return false;
  }

  if (!proofMatchesRoot(root, proof)) {
    return false;
  }

  let position = randomPosition;
  let parentWeight = root.totalWeight;

  for (let level = proof.siblings.length - 1; level >= 0; level -= 1) {
    const sibling = proof.siblings[level];

    if (sibling === undefined) {
      return false;
    }

    const isLeftChild = Math.floor(proof.index / 2 ** level) % 2 === 0;
    const currentWeight = parentWeight - sibling.weight;

    if (currentWeight < 0n) {
      return false;
    }

    if (isLeftChild) {
      if (position >= currentWeight) {
        return false;
      }
    } else {
      if (position < sibling.weight) {
        return false;
      }

      position -= sibling.weight;
    }

    parentWeight = currentWeight;
  }

  return parentWeight === proof.weight && position < proof.weight;
}

export function removeSelectedHolder(
  root: MerkleSumRoot,
  proof: MerkleSumProof,
): MerkleSumRoot {
  if (!proofMatchesRoot(root, proof) || proof.weight <= 0n) {
    throw new MerkleSumValidationError("proof does not match the active Merkle-sum root");
  }

  let node: MerkleSumNode = leafNode(proof.index, proof.account, 0n);
  let nodeIndex = proof.index;

  for (const sibling of proof.siblings) {
    node = nodeIndex % 2 === 0 ? parentNode(node, sibling) : parentNode(sibling, node);
    nodeIndex = Math.floor(nodeIndex / 2);
  }

  return {
    hash: node.hash,
    totalWeight: root.totalWeight - proof.weight,
    leafCount: root.leafCount,
  };
}

function proofMatchesRoot(root: MerkleSumRoot, proof: MerkleSumProof): boolean {
  if (
    !Number.isSafeInteger(proof.index) ||
    proof.index < 0 ||
    proof.index >= root.leafCount ||
    proof.weight < 0n ||
    proof.siblings.length !== treeHeight(root.leafCount)
  ) {
    return false;
  }

  let node = leafNode(proof.index, proof.account, proof.weight);
  let nodeIndex = proof.index;

  for (const sibling of proof.siblings) {
    if (sibling.weight < 0n) {
      return false;
    }

    node = nodeIndex % 2 === 0 ? parentNode(node, sibling) : parentNode(sibling, node);
    nodeIndex = Math.floor(nodeIndex / 2);
  }

  return node.hash === root.hash && node.weight === root.totalWeight;
}

function buildLevels(holders: readonly HolderWeight[]): readonly (readonly MerkleSumNode[])[] {
  const leafCapacity = nextPowerOfTwo(holders.length);
  const firstLevel = holders.map((holder, index) => leafNode(index, holder.account, holder.weight));

  while (firstLevel.length < leafCapacity) {
    firstLevel.push({ hash: ZERO_HASH, weight: 0n });
  }

  const levels: MerkleSumNode[][] = [firstLevel];
  let currentLevel = firstLevel;

  while (currentLevel.length > 1) {
    const nextLevel: MerkleSumNode[] = [];

    for (let index = 0; index < currentLevel.length; index += 2) {
      const left = currentLevel[index];
      const right = currentLevel[index + 1];

      if (left === undefined || right === undefined) {
        throw new MerkleSumValidationError("Merkle-sum tree must have complete levels");
      }

      nextLevel.push(parentNode(left, right));
    }

    levels.push(nextLevel);
    currentLevel = nextLevel;
  }

  return levels;
}

function validateHolders(holders: readonly HolderWeight[], allowZeroWeights: boolean): void {
  if (holders.length === 0) {
    throw new MerkleSumValidationError("a Merkle-sum tree requires at least one holder");
  }

  let previousAddress: string | undefined;

  for (const holder of holders) {
    const normalizedAddress = getAddress(holder.account).toLowerCase();

    if (holder.weight < 0n || (!allowZeroWeights && holder.weight === 0n)) {
      throw new MerkleSumValidationError("holder weights must be positive");
    }

    if (previousAddress !== undefined && normalizedAddress <= previousAddress) {
      throw new MerkleSumValidationError("holders must be unique and sorted by address");
    }

    previousAddress = normalizedAddress;
  }
}

function leafNode(index: number, account: Address, weight: bigint): MerkleSumNode {
  return {
    hash: keccak256(
      encodeAbiParameters(
        [
          { type: "bytes32" },
          { type: "uint256" },
          { type: "address" },
          { type: "uint256" },
        ],
        [LEAF_DOMAIN, BigInt(index), getAddress(account), weight],
      ),
    ),
    weight,
  };
}

function parentNode(left: MerkleSumNode, right: MerkleSumSibling): MerkleSumNode {
  return {
    hash: keccak256(
      encodeAbiParameters(
        [
          { type: "bytes32" },
          { type: "bytes32" },
          { type: "uint256" },
          { type: "bytes32" },
          { type: "uint256" },
        ],
        [NODE_DOMAIN, left.hash, left.weight, right.hash, right.weight],
      ),
    ),
    weight: left.weight + right.weight,
  };
}

function nextPowerOfTwo(value: number): number {
  let power = 1;

  while (power < value) {
    power *= 2;
  }

  return power;
}

function treeHeight(leafCount: number): number {
  let height = 0;
  let capacity = nextPowerOfTwo(leafCount);

  while (capacity > 1) {
    height += 1;
    capacity = Math.floor(capacity / 2);
  }

  return height;
}
