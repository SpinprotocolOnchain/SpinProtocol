// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.36;

/// @notice Minimal, version-specific surface used by SPIN's Robinhood Dice adapter.
/// @dev Derived from DiceEntropy v10's public V2 integration interface.
interface IDiceEntropyV2 {
    function requestV2(address provider, bytes32 userRandomNumber, uint32 gasLimit)
        external
        payable
        returns (uint64 assignedSequenceNumber);

    function getFeeV2(address provider, uint32 gasLimit) external view returns (uint128 feeAmount);

    function refundRequest(address provider, uint64 sequenceNumber) external;
}
