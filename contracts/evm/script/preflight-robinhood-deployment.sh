#!/usr/bin/env sh
set -eu

: "${EVM_RPC_URL:?Set EVM_RPC_URL to an archive-capable Robinhood RPC endpoint}"
: "${FACTORY_OWNER:?Set FACTORY_OWNER to the deployed Safe or timelock address}"
: "${ELIGIBILITY_TOKEN:?Set ELIGIBILITY_TOKEN to the reviewed immutable ERC-20 address}"
: "${SNAPSHOT_APPROVER:?Set SNAPSHOT_APPROVER to the production Safe or timelock address}"

chain_id="$(cast chain-id --rpc-url "$EVM_RPC_URL")"
if [ "$chain_id" != "4663" ]; then
  echo "Expected Robinhood Chain ID 4663, got $chain_id." >&2
  exit 1
fi

for contract_address in "$FACTORY_OWNER" "$ELIGIBILITY_TOKEN" "$SNAPSHOT_APPROVER"; do
  code="$(cast code "$contract_address" --rpc-url "$EVM_RPC_URL")"
  if [ "$code" = "0x" ]; then
    echo "Required address has no deployed contract code: $contract_address" >&2
    exit 1
  fi
done

echo "Preflight passed: Robinhood Chain, contract-based governance and token code are present."
echo "Record the following eligibility-token runtime hash in the deployment manifest:"
cast keccak "$(cast code "$ELIGIBILITY_TOKEN" --rpc-url "$EVM_RPC_URL")"
