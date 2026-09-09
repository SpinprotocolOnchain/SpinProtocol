import assert from "node:assert/strict";
import test from "node:test";
import type { Address } from "viem";

import type { HolderWeight } from "../../src/domain/holder-snapshot.js";
import {
  MerkleSumTree,
  MerkleSumValidationError,
  removeSelectedHolder,
  verifiesWeightedSelection,
} from "../../src/domain/merkle-sum-tree.js";

const alice = "0x1000000000000000000000000000000000000001" as Address;
const bob = "0x2000000000000000000000000000000000000002" as Address;
const carol = "0x3000000000000000000000000000000000000003" as Address;

const holders: readonly HolderWeight[] = [
  { account: alice, weight: 50n },
  { account: bob, weight: 30n },
  { account: carol, weight: 20n },
];

test("maps every random position to exactly one weighted holder", () => {
  const tree = new MerkleSumTree(holders);
  const proofs = [tree.getProof(0), tree.getProof(1), tree.getProof(2)];

  for (let position = 0n; position < 100n; position += 1n) {
    const matches = proofs.filter((proof) => verifiesWeightedSelection(tree.root, position, proof));
    assert.equal(matches.length, 1);
  }

  assert.equal(verifiesWeightedSelection(tree.root, 49n, proofs[0]!), true);
  assert.equal(verifiesWeightedSelection(tree.root, 50n, proofs[1]!), true);
  assert.equal(verifiesWeightedSelection(tree.root, 80n, proofs[2]!), true);
});

test("removes a paid holder before the next weighted draw", () => {
  const tree = new MerkleSumTree(holders);
  const bobProof = tree.getProof(1);
  const remainingRoot = removeSelectedHolder(tree.root, bobProof);
  const remainingTree = tree.withoutHolder(1);
  const aliceProof = remainingTree.getProof(0);
  const carolProof = remainingTree.getProof(2);

  assert.equal(remainingRoot.totalWeight, 70n);
  assert.deepEqual(remainingRoot, remainingTree.root);
  assert.equal(verifiesWeightedSelection(remainingRoot, 50n, bobProof), false);
  assert.equal(verifiesWeightedSelection(remainingRoot, 50n, carolProof), true);
  assert.equal(verifiesWeightedSelection(remainingRoot, 49n, aliceProof), true);
});

test("rejects duplicate or unsorted holder input", () => {
  assert.throws(
    () =>
      new MerkleSumTree([
        { account: bob, weight: 1n },
        { account: alice, weight: 1n },
      ]),
    MerkleSumValidationError,
  );

  assert.throws(
    () =>
      new MerkleSumTree([
        { account: alice, weight: 1n },
        { account: alice, weight: 1n },
      ]),
    MerkleSumValidationError,
  );
});
