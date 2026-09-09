// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Verifies SPIN_MERKLE_SUM_*_V1 proofs produced by the backend.
library MerkleSumProof {
    bytes32 internal constant LEAF_DOMAIN = keccak256("SPIN_MERKLE_SUM_LEAF_V1");
    bytes32 internal constant NODE_DOMAIN = keccak256("SPIN_MERKLE_SUM_NODE_V1");

    struct Sibling {
        bytes32 hash;
        uint256 weight;
    }

    function verifiesSelection(
        bytes32 rootHash,
        uint256 rootWeight,
        uint32 leafCount,
        uint256 randomPosition,
        uint256 index,
        address account,
        uint256 weight,
        Sibling[] calldata siblings
    ) internal pure returns (bool) {
        if (weight == 0 || randomPosition >= rootWeight || index >= leafCount) {
            return false;
        }
        if (siblings.length != treeHeight(leafCount)) return false;

        bytes32 hash = keccak256(abi.encode(LEAF_DOMAIN, index, account, weight));
        uint256 nodeWeight = weight;
        uint256 nodeIndex = index;

        // First rebuild the commitment bottom-up. Selection itself must be
        // evaluated separately from the root down; doing both in one pass
        // mixes two opposite tree directions.
        for (uint256 level = 0; level < siblings.length; ++level) {
            Sibling calldata sibling = siblings[level];
            if (nodeIndex % 2 == 0) {
                hash = keccak256(
                    abi.encode(NODE_DOMAIN, hash, nodeWeight, sibling.hash, sibling.weight)
                );
            } else {
                hash = keccak256(
                    abi.encode(NODE_DOMAIN, sibling.hash, sibling.weight, hash, nodeWeight)
                );
            }
            nodeWeight += sibling.weight;
            nodeIndex /= 2;
        }
        if (hash != rootHash || nodeWeight != rootWeight) return false;

        uint256 position = randomPosition;
        uint256 parentWeight = rootWeight;
        for (uint256 level = siblings.length; level > 0; --level) {
            uint256 treeLevel = level - 1;
            Sibling calldata sibling = siblings[treeLevel];
            if (sibling.weight > parentWeight) return false;
            uint256 currentWeight = parentWeight - sibling.weight;
            bool isLeftChild = ((index >> treeLevel) & 1) == 0;
            if (isLeftChild) {
                if (position >= currentWeight) return false;
            } else {
                if (position < sibling.weight) return false;
                position -= sibling.weight;
            }
            parentWeight = currentWeight;
        }
        return parentWeight == weight && position < weight;
    }

    function treeHeight(uint32 leafCount) internal pure returns (uint256 height) {
        if (leafCount == 0) return 0;
        uint256 capacity = 1;
        while (capacity < leafCount) capacity <<= 1;
        while (capacity > 1) {
            ++height;
            capacity >>= 1;
        }
    }

    /// @notice Rebuilds the root that results when one proven leaf is set to zero.
    /// @dev The caller must first validate that the leaf was the selected holder.
    function rootAfterRemoval(uint256 index, address account, Sibling[] calldata siblings)
        internal
        pure
        returns (bytes32 hash)
    {
        hash = keccak256(abi.encode(LEAF_DOMAIN, index, account, uint256(0)));
        uint256 nodeWeight;
        uint256 nodeIndex = index;
        for (uint256 level = 0; level < siblings.length; ++level) {
            Sibling calldata sibling = siblings[level];
            if (nodeIndex % 2 == 0) {
                hash = keccak256(
                    abi.encode(NODE_DOMAIN, hash, nodeWeight, sibling.hash, sibling.weight)
                );
            } else {
                hash = keccak256(
                    abi.encode(NODE_DOMAIN, sibling.hash, sibling.weight, hash, nodeWeight)
                );
            }
            nodeWeight += sibling.weight;
            nodeIndex /= 2;
        }
    }
}
