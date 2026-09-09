// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Ownable2Step } from "@openzeppelin/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";

/// @notice Locks round timing and makes a reviewed snapshot root available to settlement.
/// @dev This contract never calculates holder weights. It only enforces the public
/// timing gates around the manifest built from the locked configuration.
contract SpinRoundBook is Ownable2Step {
    enum RoundStatus {
        None,
        Configured,
        SnapshotProposed,
        SnapshotFinalized
    }

    struct RoundConfiguration {
        bytes32 configurationHash;
        uint64 qualificationStartBlock;
        uint64 qualificationEndBlock;
        uint64 finalityBlocks;
        uint64 reviewBlocks;
        uint256 minimumPayout;
        uint32 maximumWinners;
    }

    struct Snapshot {
        bytes32 manifestHash;
        bytes32 root;
        uint256 totalWeight;
        uint32 holderCount;
        uint64 proposedAtBlock;
        uint64 reviewEndsAtBlock;
    }

    struct Round {
        RoundStatus status;
        address snapshotPublisher;
        RoundConfiguration configuration;
        Snapshot snapshot;
    }

    error InvalidConfiguration();
    error OnlySnapshotPublisher();
    error InvalidRoundStatus(uint256 roundId, RoundStatus currentStatus);
    error SnapshotNotFinal(uint256 currentBlock, uint256 requiredBlock);
    error ReviewStillOpen(uint256 currentBlock, uint256 reviewEndsAtBlock);
    error BlockNumberOverflow();

    event SnapshotPublisherUpdated(address indexed previousPublisher, address indexed newPublisher);
    event RoundConfigured(
        uint256 indexed roundId,
        bytes32 indexed configurationHash,
        uint64 qualificationStartBlock,
        uint64 qualificationEndBlock,
        uint64 finalityBlocks,
        uint64 reviewBlocks
    );
    event SnapshotProposed(
        uint256 indexed roundId,
        bytes32 indexed manifestHash,
        bytes32 indexed root,
        uint256 totalWeight,
        uint32 holderCount,
        uint64 reviewEndsAtBlock
    );
    event SnapshotFinalized(
        uint256 indexed roundId, bytes32 indexed manifestHash, bytes32 indexed root
    );

    address public snapshotPublisher;
    uint256 public nextRoundId;
    mapping(uint256 roundId => Round round) private _rounds;

    constructor(address initialOwner, address snapshotPublisher_) Ownable(initialOwner) {
        if (snapshotPublisher_ == address(0)) revert InvalidConfiguration();
        snapshotPublisher = snapshotPublisher_;
    }

    function setSnapshotPublisher(address newSnapshotPublisher) external onlyOwner {
        if (newSnapshotPublisher == address(0)) revert InvalidConfiguration();
        address previousPublisher = snapshotPublisher;
        snapshotPublisher = newSnapshotPublisher;
        emit SnapshotPublisherUpdated(previousPublisher, newSnapshotPublisher);
    }

    /// @notice Opens the next sequential round before holders begin qualifying.
    function configureNextRound(RoundConfiguration calldata configuration)
        external
        onlyOwner
        returns (uint256 roundId)
    {
        if (
            configuration.configurationHash == bytes32(0)
                || configuration.qualificationStartBlock <= block.number
                || configuration.qualificationEndBlock <= configuration.qualificationStartBlock
                || configuration.reviewBlocks == 0 || configuration.minimumPayout == 0
                || configuration.maximumWinners == 0
        ) {
            revert InvalidConfiguration();
        }

        roundId = nextRoundId++;
        Round storage round = _rounds[roundId];
        round.status = RoundStatus.Configured;
        // Publisher rotation only applies to future rounds. An active round keeps
        // the actor that was public when its qualification window was announced.
        round.snapshotPublisher = snapshotPublisher;
        round.configuration = configuration;

        emit RoundConfigured(
            roundId,
            configuration.configurationHash,
            configuration.qualificationStartBlock,
            configuration.qualificationEndBlock,
            configuration.finalityBlocks,
            configuration.reviewBlocks
        );
    }

    /// @notice Publishes the weighted root after the locked cutoff has finalised.
    function proposeSnapshot(
        uint256 roundId,
        bytes32 manifestHash,
        bytes32 root,
        uint256 totalWeight,
        uint32 holderCount
    ) external {
        Round storage round = _rounds[roundId];
        if (msg.sender != round.snapshotPublisher) revert OnlySnapshotPublisher();
        if (round.status != RoundStatus.Configured) {
            revert InvalidRoundStatus(roundId, round.status);
        }
        if (
            manifestHash == bytes32(0) || root == bytes32(0) || totalWeight == 0 || holderCount == 0
        ) {
            revert InvalidConfiguration();
        }

        uint256 requiredBlock = uint256(round.configuration.qualificationEndBlock)
            + uint256(round.configuration.finalityBlocks);
        if (block.number < requiredBlock) revert SnapshotNotFinal(block.number, requiredBlock);

        uint256 reviewEndsAtBlock = block.number + uint256(round.configuration.reviewBlocks);
        if (reviewEndsAtBlock > type(uint64).max || block.number > type(uint64).max) {
            revert BlockNumberOverflow();
        }

        round.status = RoundStatus.SnapshotProposed;
        round.snapshot = Snapshot({
            manifestHash: manifestHash,
            root: root,
            totalWeight: totalWeight,
            holderCount: holderCount,
            proposedAtBlock: uint64(block.number),
            reviewEndsAtBlock: uint64(reviewEndsAtBlock)
        });
        emit SnapshotProposed(
            roundId, manifestHash, root, totalWeight, holderCount, uint64(reviewEndsAtBlock)
        );
    }

    /// @notice Anyone may finalize after the full public review period has elapsed.
    function finalizeSnapshot(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.status != RoundStatus.SnapshotProposed) {
            revert InvalidRoundStatus(roundId, round.status);
        }
        if (block.number < round.snapshot.reviewEndsAtBlock) {
            revert ReviewStillOpen(block.number, round.snapshot.reviewEndsAtBlock);
        }

        round.status = RoundStatus.SnapshotFinalized;
        emit SnapshotFinalized(roundId, round.snapshot.manifestHash, round.snapshot.root);
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return _rounds[roundId];
    }
}
