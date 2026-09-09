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
    error InvalidDiceSequence();

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

    constructor(
        SpinWethVault projectVault_,
        SpinRoundBook roundBook_,
        IDiceEntropyV2 entropy_,
        address provider_,
        uint32 callbackGasLimit_
    ) {
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
        if (diceSequenceForRound[roundId] != 0) revert DiceAlreadyRequested(roundId);

        uint256 fee = entropy.getFeeV2(provider, callbackGasLimit);
        uint256 requiredProjectPot = fee + round.configuration.minimumPayout;
        if (projectVault.accountedPot() < requiredProjectPot) {
            revert InsufficientProjectPot(projectVault.accountedPot(), requiredProjectPot);
        }

        uint256 availableForWinners = projectVault.accountedPot() - fee;
        SettlementMath.Result memory settlement = SettlementMath.calculate(
            availableForWinners,
            round.configuration.minimumPayout,
            round.configuration.maximumWinners,
            round.snapshot.holderCount
        );

        bytes32 context = keccak256(
            abi.encode(
                roundId,
                round.snapshot.manifestHash,
                round.snapshot.root,
                round.snapshot.totalWeight
            )
        );
        projectVault.reserveDiceFee(fee, address(this));
        projectVault.reserveSettlement(settlement.totalReserved);
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
        projectVault.restoreDiceFee(fee);
        Settlement memory settlement = settlements[roundId];
        uint256 remainingReservation = settlement.payoutPerWinner
            * (uint256(settlement.winnerCount) - uint256(settlement.winnersPaid));
        if (remainingReservation != 0) {
            projectVault.releaseReservedSettlement(remainingReservation);
        }
        delete diceSequenceForRound[roundId];
        delete reservedDiceFee[roundId];
        delete settlements[roundId];
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
        projectVault.payReservedSettlement(account, settlement.payoutPerWinner);
        emit WinnerPaid(roundId, ordinal, account, settlement.payoutPerWinner, weight);
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
