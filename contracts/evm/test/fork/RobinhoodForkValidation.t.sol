// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { DiceRobinhoodConfig } from "../../src/DiceRobinhoodConfig.sol";
import { IDiceEntropyV2 } from "../../src/interfaces/IDiceEntropyV2.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";
import { RobinhoodClock } from "../../src/libraries/RobinhoodClock.sol";
import { SpinIntegrationFactory } from "../../src/SpinIntegrationFactory.sol";
import { SpinSettlementController } from "../../src/SpinSettlementController.sol";
import { SpinWethVault } from "../../src/SpinWethVault.sol";

interface Vm {
    function createSelectFork(string calldata rpcUrl, uint256 blockNumber)
        external
        returns (uint256 forkId);
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256 value);
    function envOr(string calldata name, address defaultValue) external returns (address value);
    function envOr(string calldata name, string calldata defaultValue)
        external
        returns (string memory value);
}

contract RobinhoodClockHarness {
    function currentBlock() external view returns (uint256) {
        return RobinhoodClock.currentBlock();
    }
}

/// @notice Explicit opt-in release-gate test. It never creates a fork during normal local or CI runs.
contract RobinhoodForkValidationTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant ARB_SYS = address(0x64);

    function testForkValidatesPinnedRobinhoodDeploymentInputs() external {
        if (vm.envOr("RUN_ROBINHOOD_FORK", uint256(0)) != 1) return;

        string memory rpcUrl = vm.envOr("EVM_RPC_URL", "");
        uint256 forkBlock = vm.envOr("ROBINHOOD_FORK_BLOCK", uint256(0));
        address weth = vm.envOr("ROBINHOOD_WETH", address(0));
        address approver = vm.envOr("ROBINHOOD_SNAPSHOT_APPROVER", address(0));
        require(bytes(rpcUrl).length != 0 && forkBlock != 0, "missing pinned fork configuration");

        vm.createSelectFork(rpcUrl, forkBlock);
        require(block.chainid == DiceRobinhoodConfig.CHAIN_ID, "wrong chain");
        require(weth.code.length != 0 && approver.code.length != 0, "fork code mismatch");
        require(DiceRobinhoodConfig.ENTROPY.code.length != 0, "Dice entropy missing");
        require(DiceRobinhoodConfig.DEFAULT_PROVIDER != address(0), "Dice provider missing");

        (bool ok, bytes memory result) =
            ARB_SYS.staticcall(abi.encodeWithSignature("arbBlockNumber()"));
        require(ok && result.length == 32, "ArbSys child clock unavailable");
        require(
            RobinhoodClockHarness(address(new RobinhoodClockHarness())).currentBlock()
                == abi.decode(result, (uint256)),
            "child clock mismatch"
        );

        SpinIntegrationFactory factory = new SpinIntegrationFactory(address(this));
        factory.approveEligibilityToken(weth, weth.codehash);
        (,,, SpinSettlementController controller) = factory.createIntegration(
            SpinIntegrationFactory.IntegrationConfiguration({
                owner: address(this),
                snapshotPublisher: address(0x1111),
                snapshotApprover: approver,
                eligibilityToken: weth,
                eligibilityPolicyHash: bytes32("fork-policy"),
                settlementAsset: IWETH(weth),
                creatorTreasury: address(0x2222),
                spinHolderJackpot: address(0x3333),
                buybackReserve: address(0x4444),
                entropy: IDiceEntropyV2(DiceRobinhoodConfig.ENTROPY),
                diceProvider: DiceRobinhoodConfig.DEFAULT_PROVIDER,
                callbackGasLimit: DiceRobinhoodConfig.CALLBACK_GAS_LIMIT
            })
        );
        SpinWethVault vault = controller.projectVault();
        require(vault.factory() == address(factory), "factory not retained");
        require(
            vault.settlementController() == address(controller), "controller not atomically wired"
        );
    }
}
