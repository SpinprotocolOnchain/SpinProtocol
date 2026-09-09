// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.36;

/// @notice Immutable public deployment coordinates for the reviewed Dice v10 adapter.
/// @dev A new Dice deployment must receive a new adapter and review; do not replace these values in-place.
library DiceRobinhoodConfig {
    uint256 internal constant CHAIN_ID = 4_663;
    address internal constant ENTROPY = 0xd8A0680e7699526B57140ED4EAfdCc7219Dc0A0c;
    address internal constant DEFAULT_PROVIDER = 0x8741b8a825644D9Ef18Faf2DAB5e9b47B900F2b6;
    uint32 internal constant CALLBACK_GAS_LIMIT = 200_000;
}
