// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SettlementMath } from "../../src/libraries/SettlementMath.sol";

contract SettlementMathTest {
    function testFuzzPreservesEveryWei(
        uint96 available,
        uint96 minimumPayout,
        uint16 maximumWinners,
        uint16 holderCount
    ) external pure {
        SettlementMath.Result memory result = SettlementMath.calculate(
            available, minimumPayout, maximumWinners, holderCount
        );

        if (minimumPayout == 0 || maximumWinners == 0 || holderCount == 0) {
            require(result.winnerCount == 0, "invalid input created winners");
            require(result.totalReserved == 0, "invalid input reserved funds");
            return;
        }

        uint256 expected = maximumWinners;
        if (expected > holderCount) expected = holderCount;
        uint256 affordable = available / minimumPayout;
        if (expected > affordable) expected = affordable;

        require(result.winnerCount == expected, "incorrect winner count");
        require(result.totalReserved + result.rollover == available, "wei was lost or created");
        if (expected == 0) {
            require(result.payoutPerWinner == 0, "empty settlement has a payout");
            return;
        }
        require(result.payoutPerWinner >= minimumPayout, "winner received below minimum");
        require(result.totalReserved == result.payoutPerWinner * expected, "reserved total differs");
        require(result.rollover < expected, "rollover is not division remainder");
    }
}
