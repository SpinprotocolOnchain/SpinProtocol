// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Integer-only settlement arithmetic for a sealed WETH jackpot.
library SettlementMath {
    struct Result {
        uint256 winnerCount;
        uint256 payoutPerWinner;
        uint256 totalReserved;
        uint256 rollover;
    }

    /// @dev `available` is the project pot after the exact Dice fee has been reserved.
    function calculate(
        uint256 available,
        uint256 minimumPayout,
        uint32 maximumWinners,
        uint32 eligibleHolderCount
    ) internal pure returns (Result memory result) {
        result.rollover = available;
        if (minimumPayout == 0 || maximumWinners == 0 || eligibleHolderCount == 0) {
            return result;
        }

        uint256 affordableWinners = available / minimumPayout;
        uint256 winnerCount = maximumWinners;
        if (winnerCount > eligibleHolderCount) winnerCount = eligibleHolderCount;
        if (winnerCount > affordableWinners) winnerCount = affordableWinners;
        if (winnerCount == 0) return result;

        uint256 payoutPerWinner = available / winnerCount;
        uint256 totalReserved = payoutPerWinner * winnerCount;
        return Result({
            winnerCount: winnerCount,
            payoutPerWinner: payoutPerWinner,
            totalReserved: totalReserved,
            rollover: available - totalReserved
        });
    }
}
