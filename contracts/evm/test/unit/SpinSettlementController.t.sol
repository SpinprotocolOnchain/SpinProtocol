// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinRoundBook } from "../../src/SpinRoundBook.sol";
import { SpinSettlementController } from "../../src/SpinSettlementController.sol";
import { SpinWethVault } from "../../src/SpinWethVault.sol";
import { MerkleSumProof } from "../../src/libraries/MerkleSumProof.sol";
import { MockDiceEntropyV2 } from "../mocks/MockDiceEntropyV2.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

interface Vm {
    function roll(uint256 newHeight) external;
    function deal(address account, uint256 newBalance) external;
}

contract SpinSettlementControllerTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address private constant PROVIDER = address(0xCAFE);
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    bytes32 private constant LEAF_DOMAIN = keccak256("SPIN_MERKLE_SUM_LEAF_V1");
    bytes32 private constant NODE_DOMAIN = keccak256("SPIN_MERKLE_SUM_NODE_V1");

    function testRefusesDiceBeforeSnapshotFinalization() external {
        (SpinSettlementController controller,,) = _deploy();
        (bool ok,) = address(controller)
            .call(abi.encodeCall(controller.requestDice, (0, bytes32("user-random"))));
        require(!ok, "Dice requested before finalization");
    }

    function testBindsOnlyOneDiceSequenceToAFinalizedRound() external {
        (SpinSettlementController controller, SpinRoundBook book, SpinWethVault vault) = _deploy();
        uint256 roundId = _finalizeRound(book);

        uint64 sequence = controller.requestDice(roundId, bytes32("user-random"));
        require(sequence == 1, "unexpected sequence");
        require(controller.diceSequenceForRound(roundId) == sequence, "round not bound");
        (,, uint256 payoutPerWinner, uint32 winnerCount,) = controller.settlements(roundId);
        require(winnerCount == 1, "wrong affordable winner count");
        require(payoutPerWinner == 1.95 ether, "wrong sealed payout");
        require(vault.reservedSettlementPot() == 1.95 ether, "payout not reserved");
        require(vault.accountedPot() == 0, "later pot not separated");

        (bool duplicateOk,) = address(controller)
            .call(abi.encodeCall(controller.requestDice, (roundId, bytes32("different-random"))));
        require(!duplicateOk, "duplicate Dice request accepted");
    }

    function testRefundReopensTheSameFinalizedRoundWithoutChangingThePot() external {
        (SpinSettlementController controller, SpinRoundBook book, SpinWethVault vault) = _deploy();
        uint256 roundId = _finalizeRound(book);
        uint256 potBefore = vault.accountedPot();
        controller.requestDice(roundId, bytes32("user-random"));
        controller.refundDice(roundId);

        require(vault.accountedPot() == potBefore, "refund did not restore pot");
        require(controller.diceSequenceForRound(roundId) == 0, "round stayed blocked");
    }

    function testRefundsAndRewrapsANonZeroDiceFeeWithoutChangingThePot() external {
        uint128 diceFee = 0.01 ether;
        (SpinSettlementController controller, SpinRoundBook book, SpinWethVault vault) =
            _deployWithDiceFee(diceFee);
        uint256 roundId = _finalizeRound(book);
        uint256 potBefore = vault.accountedPot();

        controller.requestDice(roundId, bytes32("user-random"));
        require(address(controller.entropy()).balance == diceFee, "Dice did not receive its fee");
        controller.refundDice(roundId);

        require(vault.accountedPot() == potBefore, "non-zero refund changed project pot");
        require(address(controller.diceConsumer()).balance == 0, "refund was not rewrapped");
    }

    function testPaysTwoUniqueProvenWinnersAfterDiceResolves() external {
        (SpinSettlementController controller, SpinRoundBook book, SpinWethVault vault) = _deploy();
        MockWETH weth = MockWETH(payable(address(vault.settlementAsset())));
        MockDiceEntropyV2 entropy = MockDiceEntropyV2(payable(address(controller.entropy())));
        bytes32 root = _root();
        uint256 roundId = _finalizeWeightedRound(book, root);
        bytes32 randomWord = keccak256("settlement-randomness");
        uint256 aliceBefore = weth.balanceOf(ALICE);
        uint256 bobBefore = weth.balanceOf(BOB);

        uint64 sequence = controller.requestDice(roundId, bytes32("user-random"));
        entropy.reveal(sequence, randomWord);

        uint256 firstPosition = _position(randomWord, roundId, 0, 100);
        if (firstPosition < 60) {
            controller.payNextWinner(roundId, 0, ALICE, 60, _originalAliceProof());
            controller.payNextWinner(roundId, 1, BOB, 40, _remainingBobProof());
        } else {
            controller.payNextWinner(roundId, 1, BOB, 40, _originalBobProof());
            controller.payNextWinner(roundId, 0, ALICE, 60, _remainingAliceProof());
        }

        require(weth.balanceOf(ALICE) - aliceBefore == 0.975 ether, "alice not paid exactly once");
        require(weth.balanceOf(BOB) - bobBefore == 0.975 ether, "bob not paid exactly once");
        require(vault.reservedSettlementPot() == 0, "settlement reserve not exhausted");
        (,,,, uint32 winnersPaid) = controller.settlements(roundId);
        require(winnersPaid == 2, "winner count was not recorded");
    }

    function testRejectsAForgedWinnerProofAfterDiceResolves() external {
        (SpinSettlementController controller, SpinRoundBook book,) = _deploy();
        MockDiceEntropyV2 entropy = MockDiceEntropyV2(payable(address(controller.entropy())));
        uint256 roundId = _finalizeWeightedRound(book, _root());
        uint64 sequence = controller.requestDice(roundId, bytes32("user-random"));
        entropy.reveal(sequence, keccak256("settlement-randomness"));

        MerkleSumProof.Sibling[] memory forged = _originalAliceProof();
        (bool ok,) = address(controller)
            .call(abi.encodeCall(controller.payNextWinner, (roundId, 0, ALICE, 59, forged)));
        require(!ok, "forged proof paid a winner");
    }

    function _deploy()
        private
        returns (SpinSettlementController controller, SpinRoundBook book, SpinWethVault vault)
    {
        return _deployWithDiceFee(0);
    }

    function _deployWithDiceFee(uint128 diceFee)
        private
        returns (SpinSettlementController controller, SpinRoundBook book, SpinWethVault vault)
    {
        MockWETH weth = new MockWETH();
        vm.deal(address(weth), diceFee);
        vault = new SpinWethVault(
            weth, address(this), address(0xA11CE), address(0xB0B), address(0xC0DE)
        );
        weth.mint(address(this), 2 ether);
        weth.approve(address(vault), 2 ether);
        vault.fundJackpot(2 ether);

        book = new SpinRoundBook(address(this), address(this));
        MockDiceEntropyV2 entropy = new MockDiceEntropyV2(diceFee);
        controller = new SpinSettlementController(vault, book, entropy, PROVIDER, 200_000);
        vault.setSettlementController(address(controller));
    }

    function _finalizeRound(SpinRoundBook book) private returns (uint256 roundId) {
        roundId = book.configureNextRound(
            SpinRoundBook.RoundConfiguration({
                configurationHash: bytes32("configuration"),
                qualificationStartBlock: 10,
                qualificationEndBlock: 20,
                finalityBlocks: 3,
                reviewBlocks: 5,
                minimumPayout: 1 ether,
                maximumWinners: 3
            })
        );
        vm.roll(23);
        book.proposeSnapshot(roundId, bytes32("manifest"), bytes32("root"), 100, 1);
        vm.roll(28);
        book.finalizeSnapshot(roundId);
    }

    function _finalizeWeightedRound(SpinRoundBook book, bytes32 root)
        private
        returns (uint256 roundId)
    {
        roundId = book.configureNextRound(
            SpinRoundBook.RoundConfiguration({
                configurationHash: bytes32("weighted-configuration"),
                qualificationStartBlock: 10,
                qualificationEndBlock: 20,
                finalityBlocks: 3,
                reviewBlocks: 5,
                minimumPayout: 0.5 ether,
                maximumWinners: 2
            })
        );
        vm.roll(23);
        book.proposeSnapshot(roundId, bytes32("weighted-manifest"), root, 100, 2);
        vm.roll(28);
        book.finalizeSnapshot(roundId);
    }

    function _root() private pure returns (bytes32) {
        bytes32 aliceLeaf = _leaf(0, ALICE, 60);
        bytes32 bobLeaf = _leaf(1, BOB, 40);
        return keccak256(abi.encode(NODE_DOMAIN, aliceLeaf, 60, bobLeaf, 40));
    }

    function _originalAliceProof() private pure returns (MerkleSumProof.Sibling[] memory proof) {
        proof = new MerkleSumProof.Sibling[](1);
        proof[0] = MerkleSumProof.Sibling(_leaf(1, BOB, 40), 40);
    }

    function _originalBobProof() private pure returns (MerkleSumProof.Sibling[] memory proof) {
        proof = new MerkleSumProof.Sibling[](1);
        proof[0] = MerkleSumProof.Sibling(_leaf(0, ALICE, 60), 60);
    }

    function _remainingAliceProof() private pure returns (MerkleSumProof.Sibling[] memory proof) {
        proof = new MerkleSumProof.Sibling[](1);
        proof[0] = MerkleSumProof.Sibling(_leaf(1, BOB, 0), 0);
    }

    function _remainingBobProof() private pure returns (MerkleSumProof.Sibling[] memory proof) {
        proof = new MerkleSumProof.Sibling[](1);
        proof[0] = MerkleSumProof.Sibling(_leaf(0, ALICE, 0), 0);
    }

    function _leaf(uint256 index, address account, uint256 weight) private pure returns (bytes32) {
        return keccak256(abi.encode(LEAF_DOMAIN, index, account, weight));
    }

    function _position(bytes32 randomWord, uint256 roundId, uint256 ordinal, uint256 totalWeight)
        private
        pure
        returns (uint256)
    {
        uint256 limit = type(uint256).max - (type(uint256).max % totalWeight);
        for (uint256 nonce; nonce < type(uint256).max; ++nonce) {
            uint256 value = uint256(keccak256(abi.encode(randomWord, roundId, ordinal, nonce)));
            if (value < limit) return value % totalWeight;
        }
        revert("unreachable");
    }
}
