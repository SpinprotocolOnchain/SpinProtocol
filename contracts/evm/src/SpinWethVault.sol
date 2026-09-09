// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/utils/ReentrancyGuard.sol";

import { SpinRoundBook } from "./SpinRoundBook.sol";
import { RobinhoodClock } from "./libraries/RobinhoodClock.sol";

import { IWETH } from "./interfaces/IWETH.sol";

/// @notice Immutable WETH intake and protocol-fee allocation for one integrator.
/// @dev It has no owner withdrawal path and no winner-selection logic. Those
/// capabilities belong to later reviewed layers.
contract SpinWethVault is ReentrancyGuard {
    using SafeERC20 for IWETH;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant PROJECT_JACKPOT_BPS = 9_750;
    uint256 public constant CREATOR_TREASURY_BPS = 100;
    uint256 public constant SPIN_HOLDER_JACKPOT_BPS = 100;
    uint256 public constant BUYBACK_RESERVE_BPS = 50;

    error InvalidConfiguration();
    error OnlyFeeRouter();
    error OnlyFactory();
    error UnexpectedReceivedAmount(uint256 expected, uint256 received);
    error OnlySettlementController();
    error SettlementControllerAlreadySet();
    error InsufficientAccountedPot(uint256 available, uint256 required);
    error InsufficientReservedSettlement(uint256 available, uint256 required);
    error RoundFundingClosed(uint256 roundId);
    error RoundCutoffNotReached(uint256 roundId);
    error RoundPotNotSealed(uint256 roundId);
    error RoundPotAlreadySealed(uint256 roundId);

    event DepositAllocated(
        address indexed sender,
        uint256 grossAmount,
        uint256 projectJackpotAmount,
        uint256 creatorTreasuryAmount,
        uint256 spinHolderJackpotAmount,
        uint256 buybackReserveAmount
    );

    event RoundPotCredited(uint256 indexed roundId, uint256 amount);
    event RoundPotRolledOver(
        uint256 indexed fromRoundId, uint256 indexed toRoundId, uint256 amount
    );
    event RoundPotSealed(uint256 indexed roundId, uint256 amount);

    SpinRoundBook public immutable roundBook;
    IWETH public immutable settlementAsset;
    address public immutable feeRouter;
    address public immutable factory;
    address public immutable creatorTreasury;
    address public immutable spinHolderJackpot;
    address public immutable buybackReserve;
    address public settlementController;
    uint256 public accountedPot;
    uint256 public reservedSettlementPot;
    mapping(uint256 roundId => uint256 amount) public roundPot;
    mapping(uint256 roundId => uint256 amount) public roundReservedSettlement;
    mapping(uint256 roundId => uint256 amount) public roundReservedDiceFee;
    mapping(uint256 roundId => bool isSealed) public roundPotSealed;

    constructor(
        SpinRoundBook roundBook_,
        IWETH settlementAsset_,
        address factory_,
        address feeRouter_,
        address creatorTreasury_,
        address spinHolderJackpot_,
        address buybackReserve_
    ) {
        if (
            address(roundBook_) == address(0) || address(settlementAsset_) == address(0)
                || factory_ == address(0) || feeRouter_ == address(0)
                || creatorTreasury_ == address(0) || spinHolderJackpot_ == address(0)
                || buybackReserve_ == address(0) || feeRouter_ == creatorTreasury_
                || feeRouter_ == spinHolderJackpot_ || feeRouter_ == buybackReserve_
                || creatorTreasury_ == spinHolderJackpot_ || creatorTreasury_ == buybackReserve_
                || spinHolderJackpot_ == buybackReserve_
        ) {
            revert InvalidConfiguration();
        }
        roundBook = roundBook_;
        settlementAsset = settlementAsset_;
        factory = factory_;
        feeRouter = feeRouter_;
        creatorTreasury = creatorTreasury_;
        spinHolderJackpot = spinHolderJackpot_;
        buybackReserve = buybackReserve_;
    }

    /// @notice Funds an announced round through its inclusive qualification end block.
    function fundRoundJackpot(uint256 roundId, uint256 amount) external nonReentrant {
        if (msg.sender != feeRouter) revert OnlyFeeRouter();
        _requireFundingOpen(roundId);
        uint256 credited = _fundJackpot(amount);
        roundPot[roundId] += credited;
        accountedPot += credited;
        emit RoundPotCredited(roundId, credited);
    }

    function _requireFundingOpen(uint256 roundId) private view {
        SpinRoundBook.Round memory round = roundBook.getRound(roundId);
        if (roundPotSealed[roundId]) revert RoundPotAlreadySealed(roundId);
        if (
            round.status != SpinRoundBook.RoundStatus.Configured
                || RobinhoodClock.currentBlock() > round.configuration.qualificationEndBlock
        ) {
            revert RoundFundingClosed(roundId);
        }
    }

    /// @notice Anyone may seal after the cutoff; late sealing cannot admit late deposits.
    function sealRoundPot(uint256 roundId) public {
        SpinRoundBook.Round memory round = roundBook.getRound(roundId);
        if (
            round.status == SpinRoundBook.RoundStatus.None
                || RobinhoodClock.currentBlock() <= round.configuration.qualificationEndBlock
        ) {
            revert RoundCutoffNotReached(roundId);
        }
        if (!roundPotSealed[roundId]) {
            roundPotSealed[roundId] = true;
            emit RoundPotSealed(roundId, roundPot[roundId]);
        }
    }

    /// @notice Moves only an approved closed round's remainder, without charging fees again.
    function rolloverRoundPot(uint256 fromRoundId, uint256 toRoundId) external {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (!roundPotSealed[fromRoundId]) revert RoundPotNotSealed(fromRoundId);
        if (toRoundId <= fromRoundId) revert InvalidConfiguration();
        _requireFundingOpen(toRoundId);
        uint256 amount = roundPot[fromRoundId];
        roundPot[fromRoundId] = 0;
        roundPot[toRoundId] += amount;
        emit RoundPotRolledOver(fromRoundId, toRoundId, amount);
    }

    function _fundJackpot(uint256 amount) private returns (uint256 projectJackpotAmount) {
        uint256 balanceBefore = settlementAsset.balanceOf(address(this));
        settlementAsset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = settlementAsset.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert UnexpectedReceivedAmount(amount, received);

        uint256 creatorTreasuryAmount = (amount * CREATOR_TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 spinHolderJackpotAmount = (amount * SPIN_HOLDER_JACKPOT_BPS) / BPS_DENOMINATOR;
        uint256 buybackReserveAmount = (amount * BUYBACK_RESERVE_BPS) / BPS_DENOMINATOR;
        projectJackpotAmount =
            amount - creatorTreasuryAmount - spinHolderJackpotAmount - buybackReserveAmount;
        settlementAsset.safeTransfer(creatorTreasury, creatorTreasuryAmount);
        settlementAsset.safeTransfer(spinHolderJackpot, spinHolderJackpotAmount);
        settlementAsset.safeTransfer(buybackReserve, buybackReserveAmount);

        emit DepositAllocated(
            msg.sender,
            amount,
            projectJackpotAmount,
            creatorTreasuryAmount,
            spinHolderJackpotAmount,
            buybackReserveAmount
        );
    }

    /// @notice One-time wiring performed atomically by the reviewed integration factory.
    function setSettlementController(address controller) external {
        if (msg.sender != factory) revert OnlyFactory();
        if (controller == address(0)) revert InvalidConfiguration();
        if (settlementController != address(0)) revert SettlementControllerAlreadySet();
        settlementController = controller;
    }

    function reserveDiceFee(uint256 roundId, uint256 amount, address recipient)
        external
        nonReentrant
    {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (recipient == address(0)) revert InvalidConfiguration();
        if (!roundPotSealed[roundId]) revert RoundPotNotSealed(roundId);
        if (amount > roundPot[roundId]) revert InsufficientAccountedPot(roundPot[roundId], amount);
        roundPot[roundId] -= amount;
        accountedPot -= amount;
        roundReservedDiceFee[roundId] += amount;
        settlementAsset.withdraw(amount);
        (bool sent,) = recipient.call{ value: amount }("");
        if (!sent) revert InvalidConfiguration();
    }

    function restoreDiceFee(uint256 roundId, uint256 amount) external {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (amount != roundReservedDiceFee[roundId]) revert InvalidConfiguration();
        roundReservedDiceFee[roundId] = 0;
        if (
            settlementAsset.balanceOf(address(this)) < accountedPot + reservedSettlementPot + amount
        ) {
            revert UnexpectedReceivedAmount(amount, 0);
        }
        roundPot[roundId] += amount;
        accountedPot += amount;
    }

    /// @notice Moves a finalized round's entire payout budget out of the live pot.
    /// @dev Every reservation is isolated from all other round balances.
    function reserveSettlement(uint256 roundId, uint256 amount) external {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (!roundPotSealed[roundId]) revert RoundPotNotSealed(roundId);
        if (amount > roundPot[roundId]) revert InsufficientAccountedPot(roundPot[roundId], amount);
        roundPot[roundId] -= amount;
        accountedPot -= amount;
        roundReservedSettlement[roundId] += amount;
        reservedSettlementPot += amount;
    }

    /// @notice Sends a winner's WETH directly from the sealed settlement budget.
    function payReservedSettlement(uint256 roundId, address recipient, uint256 amount)
        external
        nonReentrant
    {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (recipient == address(0)) revert InvalidConfiguration();
        if (amount > roundReservedSettlement[roundId]) {
            revert InsufficientReservedSettlement(roundReservedSettlement[roundId], amount);
        }
        roundReservedSettlement[roundId] -= amount;
        reservedSettlementPot -= amount;
        settlementAsset.safeTransfer(recipient, amount);
    }

    /// @notice Returns an unplayed round reservation after Dice refunds the request.
    function releaseReservedSettlement(uint256 roundId, uint256 amount) external {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (amount > roundReservedSettlement[roundId]) {
            revert InsufficientReservedSettlement(roundReservedSettlement[roundId], amount);
        }
        roundReservedSettlement[roundId] -= amount;
        reservedSettlementPot -= amount;
        roundPot[roundId] += amount;
        accountedPot += amount;
    }

    receive() external payable { }
}
