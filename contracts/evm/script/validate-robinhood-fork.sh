#!/usr/bin/env sh
set -eu

: "${EVM_RPC_URL:?Set EVM_RPC_URL to an archive-capable Robinhood RPC endpoint}"
: "${ROBINHOOD_FORK_BLOCK:?Set a fixed Robinhood child-chain block number}"
: "${ROBINHOOD_FORK_BLOCK_HASH:?Set the expected hash of that exact block}"
: "${ROBINHOOD_WETH:?Set the reviewed Robinhood WETH contract address}"
: "${ROBINHOOD_FEE_ROUTER:?Set the reviewed fee-router contract address}"
: "${ROBINHOOD_SNAPSHOT_APPROVER:?Set the multisig or timelock approver address}"

actual_hash="$(cast block "$ROBINHOOD_FORK_BLOCK" --rpc-url "$EVM_RPC_URL" --field hash)"
if [ "$actual_hash" != "$ROBINHOOD_FORK_BLOCK_HASH" ]; then
  echo "The configured fork block hash does not match the RPC result." >&2
  exit 1
fi

RUN_ROBINHOOD_FORK=1 \
FOUNDRY_PROFILE=ci \
forge test --root contracts/evm --match-contract RobinhoodForkValidationTest -vvv
