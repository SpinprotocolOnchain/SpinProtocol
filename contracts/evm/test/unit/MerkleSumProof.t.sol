// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { MerkleSumProof } from "../../src/libraries/MerkleSumProof.sol";

contract MerkleSumProofHarness {
    function verifies(
        bytes32 root,
        uint256 rootWeight,
        uint32 leafCount,
        uint256 position,
        uint256 index,
        address account,
        uint256 weight,
        MerkleSumProof.Sibling[] calldata siblings
    ) external pure returns (bool) {
        return MerkleSumProof.verifiesSelection(
            root, rootWeight, leafCount, position, index, account, weight, siblings
        );
    }
}

contract MerkleSumProofTest {
    bytes32 private constant LEAF_DOMAIN = keccak256("SPIN_MERKLE_SUM_LEAF_V1");
    bytes32 private constant NODE_DOMAIN = keccak256("SPIN_MERKLE_SUM_NODE_V1");
    bytes32 private constant ZERO_HASH = keccak256("SPIN_MERKLE_SUM_ZERO_V1");

    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant CAROL = address(0xCA201);

    function testVerifiesEachWeightedRange() external {
        MerkleSumProofHarness harness = new MerkleSumProofHarness();
        (
            bytes32 root,
            MerkleSumProof.Sibling[] memory alice,
            MerkleSumProof.Sibling[] memory bob,
            MerkleSumProof.Sibling[] memory carol
        ) = _tree();

        require(harness.verifies(root, 100, 3, 49, 0, ALICE, 50, alice), "alice range rejected");
        require(harness.verifies(root, 100, 3, 50, 1, BOB, 30, bob), "bob range rejected");
        require(harness.verifies(root, 100, 3, 99, 2, CAROL, 20, carol), "carol range rejected");
    }

    function testRejectsAHolderOutsideItsRangeAndTamperedProof() external {
        MerkleSumProofHarness harness = new MerkleSumProofHarness();
        (bytes32 root,, MerkleSumProof.Sibling[] memory bob,) = _tree();
        require(!harness.verifies(root, 100, 3, 49, 1, BOB, 30, bob), "wrong range accepted");
        bob[0].weight = 31;
        require(!harness.verifies(root, 100, 3, 50, 1, BOB, 30, bob), "tampered proof accepted");
    }

    function _tree()
        private
        pure
        returns (
            bytes32 root,
            MerkleSumProof.Sibling[] memory alice,
            MerkleSumProof.Sibling[] memory bob,
            MerkleSumProof.Sibling[] memory carol
        )
    {
        bytes32 aliceLeaf = keccak256(abi.encode(LEAF_DOMAIN, 0, ALICE, 50));
        bytes32 bobLeaf = keccak256(abi.encode(LEAF_DOMAIN, 1, BOB, 30));
        bytes32 carolLeaf = keccak256(abi.encode(LEAF_DOMAIN, 2, CAROL, 20));
        bytes32 left = keccak256(abi.encode(NODE_DOMAIN, aliceLeaf, 50, bobLeaf, 30));
        bytes32 right = keccak256(abi.encode(NODE_DOMAIN, carolLeaf, 20, ZERO_HASH, 0));
        root = keccak256(abi.encode(NODE_DOMAIN, left, 80, right, 20));

        alice = new MerkleSumProof.Sibling[](2);
        alice[0] = MerkleSumProof.Sibling(bobLeaf, 30);
        alice[1] = MerkleSumProof.Sibling(right, 20);
        bob = new MerkleSumProof.Sibling[](2);
        bob[0] = MerkleSumProof.Sibling(aliceLeaf, 50);
        bob[1] = MerkleSumProof.Sibling(right, 20);
        carol = new MerkleSumProof.Sibling[](2);
        carol[0] = MerkleSumProof.Sibling(ZERO_HASH, 0);
        carol[1] = MerkleSumProof.Sibling(left, 80);
    }
}
