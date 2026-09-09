// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { ReentrancyGuard } from "@openzeppelin/utils/ReentrancyGuard.sol";

import { IDiceEntropyV2 } from "./interfaces/IDiceEntropyV2.sol";
import { SpinDiceConsumer } from "./SpinDiceConsumer.sol";
import { SpinRoundBook } from "./SpinRoundBook.sol";
import { SpinWethVault } from "./SpinWethVault.sol";
import { MerkleSumProof } from "./libraries/MerkleSumProof.sol";
import { SettlementMath } from "./libraries/SettlementMath.sol";

/// @notice Seals a reviewed round, obtains Dice randomness, and pays each proven winner in WETH.
contract SpinSettlementController is ReentrancyGuard {
    error RoundNotFinalized(uint256 roundId);
    error InsufficientProjectPot(uint256 available, uint256 required);
    error DiceAlreadyRequested(uint256 roundId);
    error NoPendingDiceRequest(uint256 roundId);
    error RandomnessNotResolved(uint256 roundId);
    error RoundAlreadySettled(uint256 roundId);
    error InvalidWinnerProof(uint256 roundId);
    error WalletAlreadyPaid(uint256 roundId, address account);
    error InvalidDiceSequence();
    error InvalidConfiguration();
    error RoundClosed(uint256 roundId);
    error RoundCannotRollover(uint256 roundId);

    event DiceRequested(
        uint256 indexed roundId, uint64 indexed sequenceNumber, bytes32 indexed context
    );
    event DiceRefunded(uint256 indexed roundId, uint64 indexed sequenceNumber, uint256 fee);
    event SettlementReserved(
        uint256 indexed roundId, uint256 winnerCount, uint256 payoutPerWinner, uint256 totalReserved
    );
    event WinnerPaid(
        uint256 indexed roundId,
        uint256 indexed winnerOrdinal,
        address indexed winner,
        uint256 payout,
        uint256 selectedWeight
    );

    SpinWethVault public immutable projectVault;
    SpinRoundBook public immutable roundBook;
    SpinDiceConsumer public immutable diceConsumer;
    IDiceEntropyV2 public immutable entropy;
    address public immutable provider;
    uint32 public immutable callbackGasLimit;

    mapping(uint256 roundId => bool closed) public roundClosed;

    mapping(uint256 roundId => uint64 sequenceNumber) public diceSequenceForRound;
    mapping(uint256 roundId => uint256 fee) public reservedDiceFee;

    struct Settlement {
        bytes32 remainingRoot;
        uint256 remainingWeight;
        uint256 payoutPerWinner;
        uint32 winnerCount;
        uint32 winnersPaid;
    }

    mapping(uint256 roundId => Settlement settlement) public settlements;
    mapping(uint256 roundId => mapping(address account => bool paid)) public walletPaid;

    constructor(
        SpinWethVault projectVault_,
        SpinRoundBook roundBook_,
        IDiceEntropyV2 entropy_,
        address provider_,
        uint32 callbackGasLimit_
    ) {
        if (
            address(projectVault_) == address(0) || address(roundBook_) == address(0)
                || address(projectVault_.roundBook()) != address(roundBook_)
                || callbackGasLimit_ == 0
        ) revert InvalidConfiguration();
        projectVault = projectVault_;
        roundBook = roundBook_;
        entropy = entropy_;
        provider = provider_;
        callbackGasLimit = callbackGasLimit_;
        diceConsumer = new SpinDiceConsumer(address(this), entropy_, provider_, callbackGasLimit_);
    }

    /// @notice Permissionless request funded from this round's recorded WETH pot.
    function requestDice(uint256 roundId, bytes32 userRandomness)
        external
        nonReentrant
        returns (uint64 sequenceNumber)
    {
        SpinRoundBook.Round memory round = roundBook.getRound(roundId);
        if (round.status != SpinRoundBook.RoundStatus.SnapshotFinalized) {
            revert RoundNotFinalized(roundId);
        }
        if (roundClosed[roundId]) revert RoundClosed(roundId);
        if (diceSequenceForRound[roundId] != 0) revert DiceAlreadyRequested(roundId);

        projectVault.sealRoundPot(roundId);
        uint256 fee = entropy.getFeeV2(provider, callbackGasLimit);
        Settlement memory previous = settlements[roundId];
        uint256 requiredProjectPot = fee
            + (previous.winnerCount == 0
                    ? round.configuration.minimumPayout
                    : previous.payoutPerWinner * previous.winnerCount);
        uint256 pot = projectVault.roundPot(roundId);
        if (pot < requiredProjectPot) revert InsufficientProjectPot(pot, requiredProjectPot);

        SettlementMath.Result memory settlement;
        if (previous.winnerCount == 0) {
            settlement = SettlementMath.calculate(
                pot - fee,
                round.configuration.minimumPayout,
                round.configuration.maximumWinners,
                round.snapshot.holderCount
            );
        } else {
            settlement.winnerCount = previous.winnerCount;
            settlement.payoutPerWinner = previous.payoutPerWinner;
            settlement.totalReserved = previous.payoutPerWinner * previous.winnerCount;
        }

        bytes32 context = keccak256(
            abi.encode(
                roundId,
                round.snapshot.manifestHash,
                round.snapshot.root,
                round.snapshot.totalWeight
            )
        );
        projectVault.reserveDiceFee(roundId, fee, address(this));
        projectVault.reserveSettlement(roundId, settlement.totalReserved);
        sequenceNumber = diceConsumer.requestRandomness{ value: fee }(context, userRandomness);
        if (sequenceNumber == 0) revert InvalidDiceSequence();
        diceSequenceForRound[roundId] = sequenceNumber;
        reservedDiceFee[roundId] = fee;
        settlements[roundId] = Settlement({
            remainingRoot: round.snapshot.root,
            remainingWeight: round.snapshot.totalWeight,
            payoutPerWinner: settlement.payoutPerWinner,
            winnerCount: uint32(settlement.winnerCount),
            winnersPaid: 0
        });
        emit DiceRequested(roundId, sequenceNumber, context);
        emit SettlementReserved(
            roundId, settlement.winnerCount, settlement.payoutPerWinner, settlement.totalReserved
        );
    }

    function refundDice(uint256 roundId) external nonReentrant {
        uint64 sequenceNumber = diceSequenceForRound[roundId];
        uint256 fee = reservedDiceFee[roundId];
        if (sequenceNumber == 0) revert NoPendingDiceRequest(roundId);

        diceConsumer.refundRandomness(sequenceNumber);
        diceConsumer.wrapRefund(projectVault.settlementAsset(), address(projectVault), fee);
        projectVault.restoreDiceFee(roundId, fee);
        Settlement memory settlement = settlements[roundId];
        uint256 remainingReservation = settlement.payoutPerWinner
            * (uint256(settlement.winnerCount) - uint256(settlement.winnersPaid));
        if (remainingReservation != 0) {
            projectVault.releaseReservedSettlement(roundId, remainingReservation);
        }
        delete diceSequenceForRound[roundId];
        delete reservedDiceFee[roundId];
        // Keep the original winner count and payout fixed across retries.
        emit DiceRefunded(roundId, sequenceNumber, fee);
    }

    /// @notice Pays the next deterministic winner; anybody may submit its public proof.
    /// @dev The recipient never signs or claims. A valid proof causes a direct WETH transfer.
    function payNextWinner(
        uint256 roundId,
        uint256 index,
        address account,
        uint256 weight,
        MerkleSumProof.Sibling[] calldata siblings
    ) external nonReentrant {
        if (walletPaid[roundId][account]) {
            revert WalletAlreadyPaid(roundId, account);
        }
        Settlement storage settlement = settlements[roundId];
        if (settlement.winnerCount == 0 || settlement.winnersPaid >= settlement.winnerCount) {
            revert RoundAlreadySettled(roundId);
        }
        uint64 sequenceNumber = diceSequenceForRound[roundId];
        SpinDiceConsumer.Request memory request = diceConsumer.getRequest(sequenceNumber);
        if (request.status != SpinDiceConsumer.RequestStatus.Resolved) {
            revert RandomnessNotResolved(roundId);
        }
        SpinRoundBook.Round memory round = roundBook.getRound(roundId);
        uint256 position = _uniformPosition(
            request.randomWord, roundId, settlement.winnersPaid, settlement.remainingWeight
        );
        if (!MerkleSumProof.verifiesSelection(
                settlement.remainingRoot,
                settlement.remainingWeight,
                round.snapshot.holderCount,
                position,
                index,
                account,
                weight,
                siblings
            )) revert InvalidWinnerProof(roundId);

        settlement.remainingRoot = MerkleSumProof.rootAfterRemoval(index, account, siblings);
        settlement.remainingWeight -= weight;
        uint256 ordinal = settlement.winnersPaid++;
        walletPaid[roundId][account] = true;
        projectVault.payReservedSettlement(roundId, account, settlement.payoutPerWinner);
        emit WinnerPaid(roundId, ordinal, account, settlement.payoutPerWinner, weight);
    }

    /// @notice Carries dust, an underfunded draw, or an expired round into its next round.
    /// @dev A permissionless caller can only select the immediately following round.
    function rolloverRound(uint256 roundId, uint256 toRoundId) external nonReentrant {
        if (roundClosed[roundId]) revert RoundClosed(roundId);
        if (toRoundId != roundId + 1) revert InvalidConfiguration();
        SpinRoundBook.Round memory round = roundBook.getRound(roundId);
        if (
            round.status != SpinRoundBook.RoundStatus.SnapshotFinalized
                && round.status != SpinRoundBook.RoundStatus.Expired
        ) {
            revert RoundNotFinalized(roundId);
        }
        Settlement memory settlement = settlements[roundId];
        if (round.status == SpinRoundBook.RoundStatus.Expired) {
            if (settlement.winnerCount != 0) revert RoundCannotRollover(roundId);
        } else if (settlement.winnerCount != 0) {
            if (settlement.winnersPaid != settlement.winnerCount) {
                revert RoundCannotRollover(roundId);
            }
        } else {
            // Oracle price changes must not allow cancellation of an otherwise funded round.
            if (projectVault.roundPot(roundId) >= round.configuration.minimumPayout) {
                revert RoundCannotRollover(roundId);
            }
        }
        projectVault.sealRoundPot(roundId);
        roundClosed[roundId] = true;
        projectVault.rolloverRoundPot(roundId, toRoundId);
    }

    function _uniformPosition(
        bytes32 randomWord,
        uint256 roundId,
        uint256 ordinal,
        uint256 totalWeight
    ) private pure returns (uint256) {
        uint256 limit = type(uint256).max - (type(uint256).max % totalWeight);
        for (uint256 nonce; nonce < type(uint256).max; ++nonce) {
            uint256 value = uint256(keccak256(abi.encode(randomWord, roundId, ordinal, nonce)));
            if (value < limit) return value % totalWeight;
        }
        revert();
    }

    receive() external payable { }
}
