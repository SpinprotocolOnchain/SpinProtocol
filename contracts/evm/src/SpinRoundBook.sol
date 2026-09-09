// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { Ownable2Step } from "@openzeppelin/access/Ownable2Step.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";

import { RobinhoodClock } from "./libraries/RobinhoodClock.sol";

/// @notice Locks round timing and makes a reviewed snapshot root available to settlement.
/// @dev This contract never calculates holder weights. It only enforces the public
/// timing gates around the manifest built from the locked configuration.
contract SpinRoundBook is Ownable2Step {
    enum RoundStatus {
        None,
        Configured,
        SnapshotProposed,
        SnapshotFinalized,
        Expired
    }

    struct RoundConfiguration {
        bytes32 configurationHash;
        uint64 qualificationStartBlock;
        uint64 qualificationEndBlock;
        uint64 finalityBlocks;
        uint64 reviewBlocks;
        uint64 snapshotExpiryBlocks;
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
        address snapshotApprover;
        RoundConfiguration configuration;
        Snapshot snapshot;
        uint64 snapshotExpiresAtBlock;
    }

    error InvalidConfiguration();
    error OnlySnapshotPublisher();
    error OnlySnapshotApprover();
    error InvalidRoundStatus(uint256 roundId, RoundStatus currentStatus);
    error SnapshotNotFinal(uint256 currentBlock, uint256 requiredBlock);
    error ReviewStillOpen(uint256 currentBlock, uint256 reviewEndsAtBlock);
    error BlockNumberOverflow();
    error SnapshotExpired(uint256 roundId);
    error SnapshotStillActive(uint256 currentBlock, uint256 expiresAtBlock);

    event SnapshotPublisherUpdated(address indexed previousPublisher, address indexed newPublisher);
    event SnapshotApproverUpdated(address indexed previousApprover, address indexed newApprover);
    event RoundConfigured(
        uint256 indexed roundId,
        bytes32 indexed configurationHash,
        uint64 qualificationStartBlock,
        uint64 qualificationEndBlock,
        uint64 finalityBlocks,
        uint64 reviewBlocks,
        uint64 snapshotExpiryBlocks
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
    event SnapshotRejected(uint256 indexed roundId, bytes32 indexed manifestHash);
    event RoundExpired(uint256 indexed roundId, uint64 snapshotExpiresAtBlock);

    address public snapshotPublisher;
    address public snapshotApprover;
    address public immutable eligibilityToken;
    bytes32 public immutable eligibilityPolicyHash;
    uint32 public immutable maximumWinnerCap;
    uint256 public nextRoundId;
    mapping(uint256 roundId => Round round) private _rounds;

    constructor(
        address initialOwner,
        address snapshotPublisher_,
        address snapshotApprover_,
        address eligibilityToken_,
        bytes32 eligibilityPolicyHash_,
        uint32 maximumWinnerCap_
    ) Ownable(initialOwner) {
        if (
            snapshotPublisher_ == address(0) || snapshotApprover_ == address(0)
                || snapshotApprover_.code.length == 0 || eligibilityToken_ == address(0)
                || eligibilityPolicyHash_ == bytes32(0) || maximumWinnerCap_ == 0
        ) revert InvalidConfiguration();
        snapshotPublisher = snapshotPublisher_;
        snapshotApprover = snapshotApprover_;
        eligibilityToken = eligibilityToken_;
        eligibilityPolicyHash = eligibilityPolicyHash_;
        maximumWinnerCap = maximumWinnerCap_;
    }

    function setSnapshotPublisher(address newSnapshotPublisher) external onlyOwner {
        if (newSnapshotPublisher == address(0)) revert InvalidConfiguration();
        address previousPublisher = snapshotPublisher;
        snapshotPublisher = newSnapshotPublisher;
        emit SnapshotPublisherUpdated(previousPublisher, newSnapshotPublisher);
    }

    function setSnapshotApprover(address newSnapshotApprover) external onlyOwner {
        if (newSnapshotApprover == address(0) || newSnapshotApprover.code.length == 0) {
            revert InvalidConfiguration();
        }
        address previousApprover = snapshotApprover;
        snapshotApprover = newSnapshotApprover;
        emit SnapshotApproverUpdated(previousApprover, newSnapshotApprover);
    }

    /// @notice Opens the next sequential round before holders begin qualifying.
    function configureNextRound(RoundConfiguration calldata configuration)
        external
        onlyOwner
        returns (uint256 roundId)
    {
        if (
            configuration.configurationHash == bytes32(0)
                || configuration.qualificationStartBlock <= RobinhoodClock.currentBlock()
                || configuration.qualificationEndBlock <= configuration.qualificationStartBlock
                || configuration.finalityBlocks == 0 || configuration.reviewBlocks == 0
                || configuration.snapshotExpiryBlocks < configuration.reviewBlocks
                || configuration.minimumPayout == 0 || configuration.maximumWinners == 0
                || configuration.maximumWinners > maximumWinnerCap
        ) {
            revert InvalidConfiguration();
        }

        roundId = nextRoundId++;
        Round storage round = _rounds[roundId];
        round.status = RoundStatus.Configured;
        // Publisher rotation only applies to future rounds. An active round keeps
        // the actor that was public when its qualification window was announced.
        round.snapshotPublisher = snapshotPublisher;
        round.snapshotApprover = snapshotApprover;
        round.configuration = configuration;

        uint256 snapshotExpiresAtBlock = uint256(configuration.qualificationEndBlock)
            + uint256(configuration.finalityBlocks) + uint256(configuration.snapshotExpiryBlocks);
        if (snapshotExpiresAtBlock > type(uint64).max) revert BlockNumberOverflow();
        round.snapshotExpiresAtBlock = uint64(snapshotExpiresAtBlock);

        emit RoundConfigured(
            roundId,
            configuration.configurationHash,
            configuration.qualificationStartBlock,
            configuration.qualificationEndBlock,
            configuration.finalityBlocks,
            configuration.reviewBlocks,
            configuration.snapshotExpiryBlocks
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
        uint256 currentBlock = RobinhoodClock.currentBlock();
        if (currentBlock >= round.snapshotExpiresAtBlock) revert SnapshotExpired(roundId);
        if (
            manifestHash == bytes32(0) || root == bytes32(0) || totalWeight == 0 || holderCount == 0
        ) {
            revert InvalidConfiguration();
        }

        uint256 requiredBlock = uint256(round.configuration.qualificationEndBlock)
            + uint256(round.configuration.finalityBlocks);
        if (currentBlock < requiredBlock) revert SnapshotNotFinal(currentBlock, requiredBlock);

        uint256 reviewEndsAtBlock = currentBlock + uint256(round.configuration.reviewBlocks);
        if (reviewEndsAtBlock > type(uint64).max || currentBlock > type(uint64).max) {
            revert BlockNumberOverflow();
        }

        round.status = RoundStatus.SnapshotProposed;
        round.snapshot = Snapshot({
            manifestHash: manifestHash,
            root: root,
            totalWeight: totalWeight,
            holderCount: holderCount,
            proposedAtBlock: uint64(currentBlock),
            reviewEndsAtBlock: uint64(reviewEndsAtBlock)
        });
        emit SnapshotProposed(
            roundId, manifestHash, root, totalWeight, holderCount, uint64(reviewEndsAtBlock)
        );
    }

    /// @notice A code-bearing multisig or timelock accepts a root after review.
    function finalizeSnapshot(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (msg.sender != round.snapshotApprover) revert OnlySnapshotApprover();
        if (round.status != RoundStatus.SnapshotProposed) {
            revert InvalidRoundStatus(roundId, round.status);
        }
        uint256 currentBlock = RobinhoodClock.currentBlock();
        if (currentBlock >= round.snapshotExpiresAtBlock) revert SnapshotExpired(roundId);
        if (currentBlock < round.snapshot.reviewEndsAtBlock) {
            revert ReviewStillOpen(currentBlock, round.snapshot.reviewEndsAtBlock);
        }

        round.status = RoundStatus.SnapshotFinalized;
        emit SnapshotFinalized(roundId, round.snapshot.manifestHash, round.snapshot.root);
    }

    function rejectSnapshot(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (msg.sender != round.snapshotApprover) revert OnlySnapshotApprover();
        if (round.status != RoundStatus.SnapshotProposed) {
            revert InvalidRoundStatus(roundId, round.status);
        }
        bytes32 manifestHash = round.snapshot.manifestHash;
        delete round.snapshot;
        round.status = RoundStatus.Configured;
        emit SnapshotRejected(roundId, manifestHash);
    }

    function expireRound(uint256 roundId) external {
        Round storage round = _rounds[roundId];
        if (round.status != RoundStatus.Configured && round.status != RoundStatus.SnapshotProposed)
        {
            revert InvalidRoundStatus(roundId, round.status);
        }
        uint256 currentBlock = RobinhoodClock.currentBlock();
        if (currentBlock < round.snapshotExpiresAtBlock) {
            revert SnapshotStillActive(currentBlock, round.snapshotExpiresAtBlock);
        }
        round.status = RoundStatus.Expired;
        emit RoundExpired(roundId, round.snapshotExpiresAtBlock);
    }

    function getRound(uint256 roundId) external view returns (Round memory) {
        return _rounds[roundId];
    }
}
