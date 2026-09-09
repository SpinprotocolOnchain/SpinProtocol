// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinRoundBook } from "../../src/SpinRoundBook.sol";

interface Vm {
    function roll(uint256 newHeight) external;
    function prank(address msgSender) external;
}

contract SpinRoundBookTest {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testRejectsZeroFinalityToKeepSnapshotAfterFundingCutoff() external {
        SpinRoundBook book = _book(address(this), address(this));
        (bool ok,) = address(book)
            .call(abi.encodeCall(book.configureNextRound, (_configuration(10, 20, 0, 5))));
        require(!ok, "snapshot could be proposed during funding cutoff block");
    }

    function testLocksTimingBeforeTheQualificationWindow() external {
        SpinRoundBook book = _book(address(this), address(this));
        SpinRoundBook.RoundConfiguration memory configuration = _configuration(10, 20, 3, 5);

        uint256 roundId = book.configureNextRound(configuration);
        SpinRoundBook.Round memory round = book.getRound(roundId);

        require(round.status == SpinRoundBook.RoundStatus.Configured, "round not configured");
        require(
            round.configuration.configurationHash == configuration.configurationHash, "hash changed"
        );
    }

    function testRefusesASnapshotBeforeTheConfiguredFinalityDepth() external {
        SpinRoundBook book = _book(address(this), address(this));
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
        SpinRoundBook book = _book(address(this), address(this));
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
        SpinRoundBook book = _book(address(this), address(this));
        uint256 roundId = book.configureNextRound(_configuration(10, 20, 3, 5));
        address replacementPublisher = address(0xBEEF);
        book.setSnapshotPublisher(replacementPublisher);
        vm.roll(23);

        book.proposeSnapshot(roundId, bytes32("manifest"), bytes32("root"), 100, 1);
        SpinRoundBook.Round memory round = book.getRound(roundId);
        require(round.snapshotPublisher == address(this), "publisher changed retroactively");
    }

    function testApproverCanRejectAndReplaceAProposedSnapshot() external {
        SpinRoundBook book = _book(address(this), address(this));
        uint256 roundId = book.configureNextRound(_configuration(10, 20, 3, 5));
        vm.roll(23);
        book.proposeSnapshot(roundId, bytes32("bad-manifest"), bytes32("bad-root"), 100, 1);
        book.rejectSnapshot(roundId);
        book.proposeSnapshot(roundId, bytes32("correct-manifest"), bytes32("correct-root"), 100, 1);
        vm.roll(28);
        book.finalizeSnapshot(roundId);
        SpinRoundBook.Round memory round = book.getRound(roundId);
        require(
            round.snapshot.manifestHash == bytes32("correct-manifest"), "replacement was not used"
        );
    }

    function testPublisherCannotFinalizeWithoutTheSeparateApprover() external {
        address publisher = address(0xBEEF);
        SpinRoundBook book = _book(publisher, address(this));
        uint256 roundId = book.configureNextRound(_configuration(10, 20, 3, 5));
        vm.roll(23);
        vm.prank(publisher);
        book.proposeSnapshot(roundId, bytes32("manifest"), bytes32("root"), 100, 1);
        vm.roll(28);
        vm.prank(publisher);
        (bool finalized,) = address(book).call(abi.encodeCall(book.finalizeSnapshot, (roundId)));
        require(!finalized, "publisher finalized its own root");
        book.finalizeSnapshot(roundId);
    }

    function testAnyoneCanExpireAnUnusableRoundAfterItsPrecommittedDeadline() external {
        SpinRoundBook book = _book(address(this), address(this));
        uint256 roundId = book.configureNextRound(_configuration(10, 20, 3, 5));
        vm.roll(43);
        book.expireRound(roundId);
        require(
            book.getRound(roundId).status == SpinRoundBook.RoundStatus.Expired, "round not expired"
        );
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
            snapshotExpiryBlocks: 20,
            minimumPayout: 1 ether,
            maximumWinners: 3
        });
    }

    function _book(address publisher, address approver) private returns (SpinRoundBook) {
        return new SpinRoundBook(
            address(this), publisher, approver, address(this), bytes32("policy"), 32
        );
    }
}
