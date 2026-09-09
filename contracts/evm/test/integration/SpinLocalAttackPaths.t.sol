// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinFeeRouter } from "../../src/SpinFeeRouter.sol";
import { SpinIntegrationFactory } from "../../src/SpinIntegrationFactory.sol";
import { SpinRoundBook } from "../../src/SpinRoundBook.sol";
import { SpinSettlementController } from "../../src/SpinSettlementController.sol";
import { SpinWethVault } from "../../src/SpinWethVault.sol";
import { MockDiceEntropyV2 } from "../mocks/MockDiceEntropyV2.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

interface Vm {
    function roll(uint256 newHeight) external;
}

/// @notice Integration-level negative paths across the factory, router and vault boundary.
contract SpinLocalAttackPathsTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant PROVIDER = address(0xD1CE);

    function testFactoryRejectsAnEligibilityTokenWithoutGovernanceApproval() external {
        SpinIntegrationFactory factory = new SpinIntegrationFactory(address(this));
        MockWETH weth = new MockWETH();
        MockDiceEntropyV2 entropy = new MockDiceEntropyV2(0);
        (bool created,) = address(factory)
            .call(abi.encodeCall(factory.createIntegration, (_configuration(weth, entropy))));
        require(!created, "unapproved eligibility token accepted");
    }

    function testRouterCannotFundAfterTheQualificationCutoff() external {
        vm.roll(10);
        (SpinRoundBook book, SpinFeeRouter router, SpinWethVault vault, MockWETH weth,) = _deploy();
        uint256 roundId = _configure(book, 20, 30);
        weth.mint(address(this), 2 ether);
        weth.approve(address(router), 2 ether);
        vm.roll(31);
        (bool funded,) =
            address(router).call(abi.encodeCall(router.fundRoundJackpot, (roundId, 2 ether)));
        require(!funded, "late router funding accepted");
        require(vault.roundPot(roundId) == 0, "late funding changed round pot");
        require(weth.balanceOf(address(router)) == 0, "router retained payer funds after revert");
    }

    function testMissingSnapshotExpiresAndRollsOnlyIntoTheNextRound() external {
        vm.roll(10);
        (
            SpinRoundBook book,
            SpinFeeRouter router,
            SpinWethVault vault,,
            SpinSettlementController controller
        ) = _deploy();
        uint256 expiredRound = _configure(book, 20, 30);
        uint256 nextRound = _configure(book, 60, 70);
        MockWETH weth = MockWETH(payable(address(vault.settlementAsset())));
        weth.mint(address(this), 2 ether);
        weth.approve(address(router), 2 ether);
        router.fundRoundJackpot(expiredRound, 2 ether);
        uint256 fundedPot = vault.roundPot(expiredRound);

        vm.roll(53);
        book.expireRound(expiredRound);
        controller.rolloverRound(expiredRound, nextRound);
        require(vault.roundPot(expiredRound) == 0, "expired pot not cleared");
        require(vault.roundPot(nextRound) == fundedPot, "expired pot was redirected or lost");
    }

    function _deploy()
        private
        returns (
            SpinRoundBook book,
            SpinFeeRouter router,
            SpinWethVault vault,
            MockWETH weth,
            SpinSettlementController controller
        )
    {
        weth = new MockWETH();
        MockDiceEntropyV2 entropy = new MockDiceEntropyV2(0);
        SpinIntegrationFactory factory = new SpinIntegrationFactory(address(this));
        factory.approveEligibilityToken(address(weth), address(weth).codehash);
        (book, router, vault, controller) = factory.createIntegration(_configuration(weth, entropy));
    }

    function _configuration(MockWETH weth, MockDiceEntropyV2 entropy)
        private
        view
        returns (SpinIntegrationFactory.IntegrationConfiguration memory)
    {
        return SpinIntegrationFactory.IntegrationConfiguration({
            owner: address(this),
            snapshotPublisher: address(this),
            snapshotApprover: address(this),
            eligibilityToken: address(weth),
            eligibilityPolicyHash: bytes32("attack-policy"),
            settlementAsset: weth,
            creatorTreasury: address(0x1111),
            spinHolderJackpot: address(0x2222),
            buybackReserve: address(0x3333),
            entropy: entropy,
            diceProvider: PROVIDER,
            callbackGasLimit: 200_000
        });
    }

    function _configure(SpinRoundBook book, uint64 start, uint64 end) private returns (uint256) {
        return book.configureNextRound(
            SpinRoundBook.RoundConfiguration({
                configurationHash: keccak256(abi.encode(start, end)),
                qualificationStartBlock: start,
                qualificationEndBlock: end,
                finalityBlocks: 3,
                reviewBlocks: 5,
                snapshotExpiryBlocks: 20,
                minimumPayout: 1 ether,
                maximumWinners: 1
            })
        );
    }
}
