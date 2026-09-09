// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinFeeRouter } from "../../src/SpinFeeRouter.sol";
import { SpinIntegrationFactory } from "../../src/SpinIntegrationFactory.sol";
import { SpinRoundBook } from "../../src/SpinRoundBook.sol";
import { SpinSettlementController } from "../../src/SpinSettlementController.sol";
import { SpinWethVault } from "../../src/SpinWethVault.sol";
import { MerkleSumProof } from "../../src/libraries/MerkleSumProof.sol";
import { MockDiceEntropyV2 } from "../mocks/MockDiceEntropyV2.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

interface Vm {
    function roll(uint256 newHeight) external;
}

/// @notice Proves the complete offline product path using only local mocks.
contract SpinLocalLifecycleTest {
    bytes32 private constant LEAF_DOMAIN = keccak256("SPIN_MERKLE_SUM_LEAF_V1");
    address private constant ALICE = address(0xA11CE);
    address private constant PROVIDER = address(0xD1CE);
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testFactoryRouterSnapshotDiceAndAutomaticPayoutWorkTogether() external {
        vm.roll(10);
        MockWETH weth = new MockWETH();
        MockDiceEntropyV2 entropy = new MockDiceEntropyV2(0);
        SpinIntegrationFactory factory = new SpinIntegrationFactory(address(this));
        factory.approveEligibilityToken(address(weth), address(weth).codehash);

        (
            SpinRoundBook book,
            SpinFeeRouter router,
            SpinWethVault vault,
            SpinSettlementController controller
        ) = factory.createIntegration(
            SpinIntegrationFactory.IntegrationConfiguration({
                owner: address(this),
                snapshotPublisher: address(this),
                snapshotApprover: address(this),
                eligibilityToken: address(weth),
                eligibilityPolicyHash: bytes32("local-policy"),
                settlementAsset: weth,
                creatorTreasury: address(0x1111),
                spinHolderJackpot: address(0x2222),
                buybackReserve: address(0x3333),
                entropy: entropy,
                diceProvider: PROVIDER,
                callbackGasLimit: 200_000
            })
        );

        uint256 roundId = book.configureNextRound(
            SpinRoundBook.RoundConfiguration({
                configurationHash: bytes32("local-round"),
                qualificationStartBlock: 20,
                qualificationEndBlock: 30,
                finalityBlocks: 3,
                reviewBlocks: 5,
                snapshotExpiryBlocks: 20,
                minimumPayout: 1 ether,
                maximumWinners: 1
            })
        );
        weth.mint(address(this), 2 ether);
        weth.approve(address(router), 2 ether);
        router.fundRoundJackpot(roundId, 2 ether);
        require(vault.roundPot(roundId) == 1.95 ether, "fee allocation incorrect");
        require(weth.allowance(address(router), address(vault)) == 0, "router retained allowance");

        vm.roll(33);
        bytes32 root = keccak256(abi.encode(LEAF_DOMAIN, uint256(0), ALICE, uint256(100)));
        book.proposeSnapshot(roundId, bytes32("local-manifest"), root, 100, 1);
        vm.roll(38);
        book.finalizeSnapshot(roundId);

        uint64 sequence = controller.requestDice(roundId, bytes32("local-randomness"));
        entropy.reveal(sequence, bytes32("resolved-randomness"));
        MerkleSumProof.Sibling[] memory proof = new MerkleSumProof.Sibling[](0);
        controller.payNextWinner(roundId, 0, ALICE, 100, proof);

        require(weth.balanceOf(ALICE) == 1.95 ether, "winner not paid");
        require(vault.roundReservedSettlement(roundId) == 0, "settlement not exhausted");
        book.configureNextRound(
            SpinRoundBook.RoundConfiguration({
                configurationHash: bytes32("next-local-round"),
                qualificationStartBlock: 40,
                qualificationEndBlock: 50,
                finalityBlocks: 3,
                reviewBlocks: 5,
                snapshotExpiryBlocks: 20,
                minimumPayout: 1 ether,
                maximumWinners: 1
            })
        );
        controller.rolloverRound(roundId, roundId + 1);
        require(controller.roundClosed(roundId), "round did not close");
    }
}
