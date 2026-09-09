// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.36;

/// @notice Callback shape invoked by DiceEntropy v10 after a valid reveal.
/// @dev The consumer must reject calls from every address except its configured oracle.
interface IDiceEntropyConsumer {
    function _entropyCallback(uint64 sequenceNumber, address provider, bytes32 randomNumber)
        external;
}
