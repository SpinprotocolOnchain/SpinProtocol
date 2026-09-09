// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IDiceEntropyV2 } from "./interfaces/IDiceEntropyV2.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { Ownable } from "@openzeppelin/access/Ownable.sol";
import { SpinRoundBook } from "./SpinRoundBook.sol";
import { SpinFeeRouter } from "./SpinFeeRouter.sol";
import { SpinSettlementController } from "./SpinSettlementController.sol";
import { SpinWethVault } from "./SpinWethVault.sol";

/// @notice Creates one fully wired SPIN integration without giving its fee router settlement rights.
/// @dev The factory has no post-deployment administrative controls. Its only privileged action is
/// the same-transaction controller wiring during `createIntegration`.
contract SpinIntegrationFactory is Ownable {
    error InvalidConfiguration();
    error EligibilityTokenNotApproved(address token);

    uint32 public constant MAXIMUM_WINNER_CAP = 32;
    mapping(address token => bytes32 codeHash) public approvedEligibilityTokenCodeHash;

    struct IntegrationConfiguration {
        address owner;
        address snapshotPublisher;
        address snapshotApprover;
        address eligibilityToken;
        bytes32 eligibilityPolicyHash;
        IWETH settlementAsset;
        address creatorTreasury;
        address spinHolderJackpot;
        address buybackReserve;
        IDiceEntropyV2 entropy;
        address diceProvider;
        uint32 callbackGasLimit;
    }

    event IntegrationCreated(
        address indexed owner,
        address indexed feeRouter,
        address indexed vault,
        address roundBook,
        address settlementController
    );
    event EligibilityTokenApproved(address indexed token, bytes32 indexed codeHash);

    constructor(address initialOwner) Ownable(initialOwner) { }

    /// @notice Adds an immutable, reviewed ERC-20 implementation to the v1 eligibility allowlist.
    function approveEligibilityToken(address token, bytes32 expectedCodeHash) external onlyOwner {
        if (
            token == address(0) || expectedCodeHash == bytes32(0)
                || token.codehash != expectedCodeHash
        ) {
            revert InvalidConfiguration();
        }
        approvedEligibilityTokenCodeHash[token] = expectedCodeHash;
        emit EligibilityTokenApproved(token, expectedCodeHash);
    }

    function createIntegration(IntegrationConfiguration calldata configuration)
        external
        returns (
            SpinRoundBook roundBook,
            SpinFeeRouter feeRouter,
            SpinWethVault vault,
            SpinSettlementController settlementController
        )
    {
        if (
            configuration.owner == address(0) || configuration.snapshotPublisher == address(0)
                || configuration.snapshotApprover.code.length == 0
                || configuration.eligibilityPolicyHash == bytes32(0)
                || address(configuration.settlementAsset) == address(0)
                || address(configuration.entropy) == address(0)
                || configuration.diceProvider == address(0) || configuration.callbackGasLimit == 0
        ) revert InvalidConfiguration();
        if (
            approvedEligibilityTokenCodeHash[configuration.eligibilityToken] == bytes32(0)
                || configuration.eligibilityToken.codehash
                    != approvedEligibilityTokenCodeHash[configuration.eligibilityToken]
        ) revert EligibilityTokenNotApproved(configuration.eligibilityToken);

        roundBook = new SpinRoundBook(
            configuration.owner,
            configuration.snapshotPublisher,
            configuration.snapshotApprover,
            configuration.eligibilityToken,
            configuration.eligibilityPolicyHash,
            MAXIMUM_WINNER_CAP
        );
        feeRouter = new SpinFeeRouter(address(this), configuration.settlementAsset);
        vault = new SpinWethVault(
            roundBook,
            configuration.settlementAsset,
            address(this),
            address(feeRouter),
            configuration.creatorTreasury,
            configuration.spinHolderJackpot,
            configuration.buybackReserve
        );
        settlementController = new SpinSettlementController(
            vault,
            roundBook,
            configuration.entropy,
            configuration.diceProvider,
            configuration.callbackGasLimit
        );
        feeRouter.setVault(vault);
        vault.setSettlementController(address(settlementController));

        emit IntegrationCreated(
            configuration.owner,
            address(feeRouter),
            address(vault),
            address(roundBook),
            address(settlementController)
        );
    }
}
