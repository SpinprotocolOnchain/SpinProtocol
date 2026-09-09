// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

import { IWETH } from "./interfaces/IWETH.sol";
import { SpinWethVault } from "./SpinWethVault.sol";

/// @notice Non-custodial WETH intake for one SPIN integration.
/// @dev It is created and bound by the integration factory. Every received WETH is
/// immediately allocated by the vault; this router has no withdrawal or admin path.
contract SpinFeeRouter {
    using SafeERC20 for IWETH;

    error InvalidConfiguration();
    error OnlyFactory();
    error VaultAlreadySet();
    error VaultNotSet();

    event VaultSet(address indexed vault);
    event RoundFunded(address indexed payer, uint256 indexed roundId, uint256 amount);

    address public immutable factory;
    IWETH public immutable settlementAsset;
    SpinWethVault public vault;

    constructor(address factory_, IWETH settlementAsset_) {
        if (factory_ == address(0) || address(settlementAsset_) == address(0)) {
            revert InvalidConfiguration();
        }
        factory = factory_;
        settlementAsset = settlementAsset_;
    }

    /// @notice One-time atomic binding by the factory that created this router.
    function setVault(SpinWethVault vault_) external {
        if (msg.sender != factory) revert OnlyFactory();
        if (address(vault_) == address(0)) revert InvalidConfiguration();
        if (address(vault) != address(0)) revert VaultAlreadySet();
        vault = vault_;
        emit VaultSet(address(vault_));
    }

    /// @notice Pulls approved WETH from the payer and credits one still-open round.
    /// @dev Any payer can contribute, but this contract cannot retain or redirect WETH.
    function fundRoundJackpot(uint256 roundId, uint256 amount) external {
        SpinWethVault targetVault = vault;
        if (address(targetVault) == address(0)) revert VaultNotSet();
        settlementAsset.safeTransferFrom(msg.sender, address(this), amount);
        settlementAsset.forceApprove(address(targetVault), amount);
        targetVault.fundRoundJackpot(roundId, amount);
        settlementAsset.forceApprove(address(targetVault), 0);
        emit RoundFunded(msg.sender, roundId, amount);
    }
}
