// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinRoundBook } from "../../src/SpinRoundBook.sol";
import { SpinWethVault } from "../../src/SpinWethVault.sol";
import { SpinSettlementController } from "../../src/SpinSettlementController.sol";
import { MerkleSumProof } from "../../src/libraries/MerkleSumProof.sol";
import { MockWETH } from "../mocks/MockWETH.sol";
import { MockDiceEntropyV2 } from "../mocks/MockDiceEntropyV2.sol";

interface RiskVm {
    function roll(uint256 height) external;
}

/// @notice Regression coverage for previously identified payment and wiring failures.
contract KnownSecurityRisksTest {
    RiskVm private constant vm = RiskVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant ATTACKER = address(0xBAD);
    bytes32 private constant LEAF = keccak256("SPIN_MERKLE_SUM_LEAF_V1");
    bytes32 private constant NODE = keccak256("SPIN_MERKLE_SUM_NODE_V1");

    function testDefenseRejectsSecondPaymentToDuplicateWallet() external {
        (
            SpinRoundBook book,,
            SpinSettlementController controller,
            MockWETH weth,
            MockDiceEntropyV2 dice
        ) = _setup();
        bytes32 leaf0 = keccak256(abi.encode(LEAF, uint256(0), ATTACKER, uint256(60)));
        bytes32 leaf1 = keccak256(abi.encode(LEAF, uint256(1), ATTACKER, uint256(40)));
        bytes32 root = keccak256(abi.encode(NODE, leaf0, uint256(60), leaf1, uint256(40)));
        _finalize(book, root, 100, 2);
        uint64 sequence = controller.requestDice(0, bytes32("user"));
        bytes32 word = bytes32("oracle");
        dice.reveal(sequence, word);
        uint256 firstIndex = uint256(
                    keccak256(abi.encode(word, uint256(0), uint256(0), uint256(0)))
                ) % 100 < 60
            ? 0
            : 1;
        MerkleSumProof.Sibling[] memory proof = new MerkleSumProof.Sibling[](1);
        proof[0] =
            firstIndex == 0 ? MerkleSumProof.Sibling(leaf1, 40) : MerkleSumProof.Sibling(leaf0, 60);
        controller.payNextWinner(0, firstIndex, ATTACKER, firstIndex == 0 ? 60 : 40, proof);
        proof[0] = MerkleSumProof.Sibling(
            keccak256(abi.encode(LEAF, firstIndex, ATTACKER, uint256(0))), 0
        );
        (bool paidTwice,) = address(controller)
            .call(
                abi.encodeCall(
                    controller.payNextWinner,
                    (0, 1 - firstIndex, ATTACKER, firstIndex == 0 ? 40 : 60, proof)
                )
            );
        require(!paidTwice, "duplicate wallet received a second prize");
        require(weth.balanceOf(ATTACKER) == 0.975 ether, "incorrect first payout");
    }

    function testDefenseOnlyFactoryCanWireSettlementController() external {
        SpinRoundBook book = new SpinRoundBook(
            address(this), address(this), address(this), address(this), bytes32("policy"), 32
        );
        book.configureNextRound(_configuration(10, 20));
        MockWETH weth = new MockWETH();
        SpinWethVault vault = new SpinWethVault(
            book,
            weth,
            address(0xFACADE),
            address(this),
            address(0x11),
            address(0x22),
            address(0x33)
        );
        (bool wired,) =
            address(vault).call(abi.encodeCall(vault.setSettlementController, (address(this))));
        require(!wired, "router could still choose its settlement controller");
    }

    function _setup()
        private
        returns (
            SpinRoundBook book,
            SpinWethVault vault,
            SpinSettlementController controller,
            MockWETH weth,
            MockDiceEntropyV2 dice
        )
    {
        book = new SpinRoundBook(
            address(this), address(this), address(this), address(this), bytes32("policy"), 32
        );
        book.configureNextRound(_configuration(10, 20));
        weth = new MockWETH();
        vault = new SpinWethVault(
            book, weth, address(this), address(this), address(0x11), address(0x22), address(0x33)
        );
        dice = new MockDiceEntropyV2(0);
        controller = new SpinSettlementController(vault, book, dice, address(0xCAFE), 200_000);
        vault.setSettlementController(address(controller));
        weth.mint(address(this), 2 ether);
        weth.approve(address(vault), 2 ether);
        vault.fundRoundJackpot(0, 2 ether);
    }

    function _configuration(uint64 start, uint64 end)
        private
        pure
        returns (SpinRoundBook.RoundConfiguration memory)
    {
        return SpinRoundBook.RoundConfiguration({
            configurationHash: bytes32("arbitrary-unverified-hash"),
            qualificationStartBlock: start,
            qualificationEndBlock: end,
            finalityBlocks: 3,
            reviewBlocks: 5,
            snapshotExpiryBlocks: 20,
            minimumPayout: 0.5 ether,
            maximumWinners: 2
        });
    }

    function _finalize(SpinRoundBook book, bytes32 root, uint256 weight, uint32 count) private {
        vm.roll(23);
        book.proposeSnapshot(0, bytes32("arbitrary-unverified-manifest"), root, weight, count);
        vm.roll(28);
        book.finalizeSnapshot(0);
    }
}
