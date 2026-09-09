import assert from "node:assert/strict";
import test from "node:test";
import type { Address, Hex } from "viem";

import {
  SnapshotManifestValidationError,
  createSnapshotManifest,
  type SnapshotManifestInput,
} from "../../src/domain/snapshot-manifest.js";
import { hashStaticExclusionList } from "../../src/domain/eligibility-policy.js";
import { hashCooldownExclusions } from "../../src/domain/winner-cooldown.js";

const alice = "0x1000000000000000000000000000000000000001" as Address;
const bob = "0x2000000000000000000000000000000000000002" as Address;
const token = "0x5000000000000000000000000000000000000005" as Address;
const bytes32 = (value: string): Hex => `0x${value.padStart(64, "0")}` as Hex;

function input(overrides: Partial<SnapshotManifestInput> = {}): SnapshotManifestInput {
  return {
    chainId: 4_663n,
    token,
    snapshot: {
      window: {
        startBlock: 100n,
        endBlock: 200n,
        startTimestamp: 1_000n,
        endTimestamp: 1_100n,
      },
      initialBalances: [
        { account: alice, balance: 60n },
        { account: bob, balance: 40n },
      ],
      transfers: [],
    },
    eligibility: {
      qualificationToken: token,
      cutoffBlockHash: bytes32("2"),
      staticExcludedAccounts: [],
      staticExclusionListHash: hashStaticExclusionList([]),
      cooldownExcludedAccounts: [],
      cooldownExclusionListHash: hashCooldownExclusions([]),
      supportedFactories: [],
      discoveredPools: [],
      accountCode: [
        { account: alice, blockHash: bytes32("2"), code: "0x" },
        { account: bob, blockHash: bytes32("2"), code: "0x" },
      ],
    },
    startBlockHash: bytes32("1"),
    endBlockHash: bytes32("2"),
    roundConfigurationHash: bytes32("3"),
    exclusionListHash: hashStaticExclusionList([]),
    cooldownExclusionListHash: hashCooldownExclusions([]),
    calculationVersionHash: bytes32("5"),
    ...overrides,
  };
}

test("creates a stable manifest from the same chain input", () => {
  const first = createSnapshotManifest(input());
  const second = createSnapshotManifest(input());

  assert.deepEqual(first, second);
  assert.equal(first.root.totalWeight, 10_000n);
  assert.equal(first.root.leafCount, 2);
});

test("changes the sealed root when transfer history changes", () => {
  const original = createSnapshotManifest(input());
  const changed = createSnapshotManifest(
    input({
      snapshot: {
        ...input().snapshot,
        transfers: [
          {
            from: alice,
            to: bob,
            amount: 20n,
            blockNumber: 150n,
            logIndex: 0,
            timestamp: 1_050n,
          },
        ],
      },
    }),
  );

  assert.notEqual(changed.root.hash, original.root.hash);
  assert.notEqual(changed.manifestHash, original.manifestHash);
});

test("changes the manifest when the preceding-round cooldown list changes", () => {
  const original = createSnapshotManifest(input());
  const cooldown = [alice];
  const changed = createSnapshotManifest(input({
    eligibility: { ...input().eligibility, cooldownExcludedAccounts: cooldown, cooldownExclusionListHash: hashCooldownExclusions(cooldown) },
    cooldownExclusionListHash: hashCooldownExclusions(cooldown),
  }));

  assert.notEqual(changed.manifestHash, original.manifestHash);
});

test("rejects a snapshot without eligible holder weight", () => {
  assert.throws(
    () =>
      createSnapshotManifest(
        input({
          snapshot: {
            ...input().snapshot,
            initialBalances: [],
          },
        }),
      ),
    SnapshotManifestValidationError,
  );
});
