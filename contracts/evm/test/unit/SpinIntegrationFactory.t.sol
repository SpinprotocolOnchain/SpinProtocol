// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinIntegrationFactory } from "../../src/SpinIntegrationFactory.sol";
import { SpinSettlementController } from "../../src/SpinSettlementController.sol";
import { SpinFeeRouter } from "../../src/SpinFeeRouter.sol";
import { SpinWethVault } from "../../src/SpinWethVault.sol";
import { MockDiceEntropyV2 } from "../mocks/MockDiceEntropyV2.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

contract SpinIntegrationFactoryTest {
    function testCreatesAndAtomicallyWiresTheOnlySettlementController() external {
        SpinIntegrationFactory factory = new SpinIntegrationFactory(address(this));
        MockWETH weth = new MockWETH();
        factory.approveEligibilityToken(address(weth), address(weth).codehash);
        MockDiceEntropyV2 entropy = new MockDiceEntropyV2(0);
        (, SpinFeeRouter feeRouter,, SpinSettlementController controller) = factory.createIntegration(
            SpinIntegrationFactory.IntegrationConfiguration({
                owner: address(this),
                snapshotPublisher: address(0x1111),
                snapshotApprover: address(this),
                eligibilityToken: address(weth),
                eligibilityPolicyHash: bytes32("policy"),
                settlementAsset: weth,
                creatorTreasury: address(0x3333),
                spinHolderJackpot: address(0x4444),
                buybackReserve: address(0x5555),
                entropy: entropy,
                diceProvider: address(0x6666),
                callbackGasLimit: 200_000
            })
        );

        SpinWethVault vault = controller.projectVault();
        require(vault.factory() == address(factory), "factory not recorded");
        require(vault.feeRouter() == address(feeRouter), "router not wired");
        require(address(feeRouter.vault()) == address(vault), "vault not retained by router");
        require(vault.settlementController() == address(controller), "controller not wired");
        (bool rewired,) =
            address(vault).call(abi.encodeCall(vault.setSettlementController, (address(this))));
        require(!rewired, "router or caller rewired controller");
    }

    function testRejectsAnEoaAsSnapshotApprover() external {
        SpinIntegrationFactory factory = new SpinIntegrationFactory(address(this));
        MockWETH weth = new MockWETH();
        factory.approveEligibilityToken(address(weth), address(weth).codehash);
        MockDiceEntropyV2 entropy = new MockDiceEntropyV2(0);
        (bool created,) = address(factory)
            .call(
                abi.encodeCall(
                    factory.createIntegration,
                    (SpinIntegrationFactory.IntegrationConfiguration({
                            owner: address(this),
                            snapshotPublisher: address(0x1111),
                            snapshotApprover: address(0xABCD),
                            eligibilityToken: address(weth),
                            eligibilityPolicyHash: bytes32("policy"),
                            settlementAsset: weth,
                            creatorTreasury: address(0x3333),
                            spinHolderJackpot: address(0x4444),
                            buybackReserve: address(0x5555),
                            entropy: entropy,
                            diceProvider: address(0x6666),
                            callbackGasLimit: 200_000
                        }))
                )
            );
        require(!created, "EOA snapshot approver accepted");
    }
}
