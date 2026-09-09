// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/utils/ReentrancyGuard.sol";

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
    error UnexpectedReceivedAmount(uint256 expected, uint256 received);
    error OnlySettlementController();
    error SettlementControllerAlreadySet();
    error InsufficientAccountedPot(uint256 available, uint256 required);
    error InsufficientReservedSettlement(uint256 available, uint256 required);

    event DepositAllocated(
        address indexed sender,
        uint256 grossAmount,
        uint256 projectJackpotAmount,
        uint256 creatorTreasuryAmount,
        uint256 spinHolderJackpotAmount,
        uint256 buybackReserveAmount
    );

    IWETH public immutable settlementAsset;
    address public immutable feeRouter;
    address public immutable creatorTreasury;
    address public immutable spinHolderJackpot;
    address public immutable buybackReserve;
    address public settlementController;
    uint256 public accountedPot;
    uint256 public reservedSettlementPot;

    constructor(
        IWETH settlementAsset_,
        address feeRouter_,
        address creatorTreasury_,
        address spinHolderJackpot_,
        address buybackReserve_
    ) {
        if (
            address(settlementAsset_) == address(0) || feeRouter_ == address(0)
                || creatorTreasury_ == address(0) || spinHolderJackpot_ == address(0)
                || buybackReserve_ == address(0) || feeRouter_ == creatorTreasury_
                || feeRouter_ == spinHolderJackpot_ || feeRouter_ == buybackReserve_
                || creatorTreasury_ == spinHolderJackpot_ || creatorTreasury_ == buybackReserve_
                || spinHolderJackpot_ == buybackReserve_
        ) {
            revert InvalidConfiguration();
        }
        settlementAsset = settlementAsset_;
        feeRouter = feeRouter_;
        creatorTreasury = creatorTreasury_;
        spinHolderJackpot = spinHolderJackpot_;
        buybackReserve = buybackReserve_;
    }

    /// @notice Pulls an explicit WETH amount from the integrator's committed fee router.
    /// @dev Balance-delta verification prevents a non-standard settlement token from
    /// silently crediting less than the recorded jackpot amount.
    function fundJackpot(uint256 amount) external nonReentrant {
        if (msg.sender != feeRouter) revert OnlyFeeRouter();

        uint256 balanceBefore = settlementAsset.balanceOf(address(this));
        settlementAsset.safeTransferFrom(msg.sender, address(this), amount);
        uint256 received = settlementAsset.balanceOf(address(this)) - balanceBefore;
        if (received != amount) revert UnexpectedReceivedAmount(amount, received);

        uint256 creatorTreasuryAmount = (amount * CREATOR_TREASURY_BPS) / BPS_DENOMINATOR;
        uint256 spinHolderJackpotAmount = (amount * SPIN_HOLDER_JACKPOT_BPS) / BPS_DENOMINATOR;
        uint256 buybackReserveAmount = (amount * BUYBACK_RESERVE_BPS) / BPS_DENOMINATOR;
        uint256 projectJackpotAmount =
            amount - creatorTreasuryAmount - spinHolderJackpotAmount - buybackReserveAmount;

        accountedPot += projectJackpotAmount;
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

    /// @notice One-time wiring performed by the linked fee router before settlement starts.
    function setSettlementController(address controller) external {
        if (msg.sender != feeRouter) revert OnlyFeeRouter();
        if (controller == address(0)) revert InvalidConfiguration();
        if (settlementController != address(0)) revert SettlementControllerAlreadySet();
        settlementController = controller;
    }

    function reserveDiceFee(uint256 amount, address recipient) external nonReentrant {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (recipient == address(0)) revert InvalidConfiguration();
        if (amount > accountedPot) revert InsufficientAccountedPot(accountedPot, amount);
        accountedPot -= amount;
        settlementAsset.withdraw(amount);
        (bool sent,) = recipient.call{ value: amount }("");
        if (!sent) revert InvalidConfiguration();
    }

    function restoreDiceFee(uint256 amount) external {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (settlementAsset.balanceOf(address(this)) < accountedPot + amount) {
            revert UnexpectedReceivedAmount(amount, 0);
        }
        accountedPot += amount;
    }

    /// @notice Moves a finalized round's entire payout budget out of the live pot.
    /// @dev Later fee-router deposits remain in accountedPot for a later round.
    function reserveSettlement(uint256 amount) external {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (amount > accountedPot) revert InsufficientAccountedPot(accountedPot, amount);
        accountedPot -= amount;
        reservedSettlementPot += amount;
    }

    /// @notice Sends a winner's WETH directly from the sealed settlement budget.
    function payReservedSettlement(address recipient, uint256 amount) external nonReentrant {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (recipient == address(0)) revert InvalidConfiguration();
        if (amount > reservedSettlementPot) {
            revert InsufficientReservedSettlement(reservedSettlementPot, amount);
        }
        reservedSettlementPot -= amount;
        settlementAsset.safeTransfer(recipient, amount);
    }

    /// @notice Returns an unplayed round reservation after Dice refunds the request.
    function releaseReservedSettlement(uint256 amount) external {
        if (msg.sender != settlementController) revert OnlySettlementController();
        if (amount > reservedSettlementPot) {
            revert InsufficientReservedSettlement(reservedSettlementPot, amount);
        }
        reservedSettlementPot -= amount;
        accountedPot += amount;
    }

    receive() external payable { }
}
