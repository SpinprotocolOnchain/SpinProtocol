// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @notice Uses Robinhood's child-chain height where the ArbSys precompile exists.
/// @dev Solidity `block.number` on Arbitrum-derived chains is the parent-chain height,
/// while RPC event ranges use the child-chain height. The fallback supports local tests.
library RobinhoodClock {
    address internal constant ARB_SYS = address(0x64);

    function currentBlock() internal view returns (uint256) {
        (bool ok, bytes memory result) =
            ARB_SYS.staticcall(abi.encodeWithSignature("arbBlockNumber()"));
        if (ok && result.length == 32) {
            uint256 childBlock = abi.decode(result, (uint256));
            if (childBlock != 0) return childBlock;
        }
        return block.number;
    }
}
