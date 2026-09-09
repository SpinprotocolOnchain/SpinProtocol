// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinRoundBook } from "../../src/SpinRoundBook.sol";

interface Vm {
    function roll(uint256 newHeight) external;
}

contract SpinRoundBookTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testLocksTimingBeforeTheQualificationWindow() external {
        SpinRoundBook book = new SpinRoundBook(address(this), address(this));
        SpinRoundBook.RoundConfiguration memory configuration = _configuration(10, 20, 3, 5);

        uint256 roundId = book.configureNextRound(configuration);
        SpinRoundBook.Round memory round = book.getRound(roundId);

        require(round.status == SpinRoundBook.RoundStatus.Configured, "round not configured");
        require(
            round.configuration.configurationHash == configuration.configurationHash, "hash changed"
        );
    }

    function testRefusesASnapshotBeforeTheConfiguredFinalityDepth() external {
        SpinRoundBook book = new SpinRoundBook(address(this), address(this));
        uint256 roundId = book.configureNextRound(_configuration(10, 20, 3, 5));
        vm.roll(22);

        (bool ok,) = address(book)
            .call(
                abi.encodeCall(
                    book.proposeSnapshot, (roundId, bytes32("manifest"), bytes32("root"), 100, 1)
                )
            );
        require(!ok, "premature snapshot accepted");
    }

    function testFinalizesOnlyAfterTheReviewPeriod() external {
        SpinRoundBook book = new SpinRoundBook(address(this), address(this));
        uint256 roundId = book.configureNextRound(_configuration(10, 20, 3, 5));
        vm.roll(23);
        book.proposeSnapshot(roundId, bytes32("manifest"), bytes32("root"), 100, 1);

        (bool earlyOk,) = address(book).call(abi.encodeCall(book.finalizeSnapshot, (roundId)));
        require(!earlyOk, "review was skipped");

        vm.roll(28);
        book.finalizeSnapshot(roundId);
        SpinRoundBook.Round memory round = book.getRound(roundId);
        require(
            round.status == SpinRoundBook.RoundStatus.SnapshotFinalized, "snapshot not finalized"
        );
    }

    function testPublisherRotationCannotTakeOverAnAlreadyConfiguredRound() external {
        SpinRoundBook book = new SpinRoundBook(address(this), address(this));
        uint256 roundId = book.configureNextRound(_configuration(10, 20, 3, 5));
        address replacementPublisher = address(0xBEEF);
        book.setSnapshotPublisher(replacementPublisher);
        vm.roll(23);

        book.proposeSnapshot(roundId, bytes32("manifest"), bytes32("root"), 100, 1);
        SpinRoundBook.Round memory round = book.getRound(roundId);
        require(round.snapshotPublisher == address(this), "publisher changed retroactively");
    }

    function _configuration(
        uint64 startBlock,
        uint64 endBlock,
        uint64 finalityBlocks,
        uint64 reviewBlocks
    ) private pure returns (SpinRoundBook.RoundConfiguration memory) {
        return SpinRoundBook.RoundConfiguration({
            configurationHash: bytes32("configuration"),
            qualificationStartBlock: startBlock,
            qualificationEndBlock: endBlock,
            finalityBlocks: finalityBlocks,
            reviewBlocks: reviewBlocks,
            minimumPayout: 1 ether,
            maximumWinners: 3
        });
    }
}
