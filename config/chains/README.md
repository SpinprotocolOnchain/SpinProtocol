# Robinhood Chain configuration

Local development uses Anvil (chain ID 31337) at `http://127.0.0.1:8545`.

Production configuration must define an **archive-capable** Robinhood Chain RPC
endpoint, chain ID, finality policy, Dice contract address and Dice provider address.
Validate the configured chain ID before signing a transaction.

The public endpoint `https://rpc.mainnet.chain.robinhood.com` is suitable for a
connection smoke test only. It may not retain the historical state required by
SPIN's `eth_getCode(account, cutoffBlock)` checks. Never build or lock a holder
snapshot from a provider that cannot answer those historical reads.

Robinhood recommends an archive endpoint through Alchemy or another supported
provider for indexing. Set that endpoint as `EVM_RPC_URL`; do not commit its API key.

## Getting an archive RPC URL

1. Create a free account at [Alchemy](https://www.alchemy.com/).
2. In the Alchemy dashboard, create an app for **Robinhood Chain Mainnet**.
3. Copy the app's HTTPS endpoint. It has this shape:
   `https://robinhood-mainnet.g.alchemy.com/v2/YOUR_API_KEY`
4. In the repository root, copy `.env.example` to `.env` and replace
   `REPLACE_WITH_YOUR_API_KEY` with the key from that endpoint.
5. Keep `.env` private. It is already ignored by Git. Never paste the key into a
   commit, GitHub issue, README or chat.

Before SPIN accepts the endpoint, it will check chain ID `4663`. For a full snapshot,
the endpoint must also answer historical `eth_getCode` calls at old block numbers.

## Alchemy plan needed for a real mainnet snapshot

The free plan is enough to prove the connection, inspect a token and run small local
checks. It is not enough for SPIN's historical holder reconstruction: Alchemy limits
`eth_getLogs` on Robinhood Mainnet to a 10-block range on Free. A real external-token
snapshot needs every `Transfer` event from deployment through the cutoff.

Use **Alchemy Pay As You Go** when SPIN begins its first mainnet snapshot. Alchemy's
current Robinhood documentation lists unlimited `eth_getLogs` block ranges for that
tier, while archive reads remain available. Enterprise is not needed for the first
production release. The reader deliberately keeps its request span configurable, so
the same audited calculation works with Alchemy PAYG or a replacement archive
provider without changing the fairness rules.

Sources: [Alchemy Robinhood `eth_getLogs` limits](https://www.alchemy.com/docs/reference/robinhood-chain-api-quickstart/eth-get-logs) and [Robinhood Chain connection guide](https://docs.robinhood.com/chain/connecting/).

## Initial LP adapters

SPIN v1 starts with the verified Uniswap v2 and v3 Robinhood Chain factories in
`backend/src/config/robinhood-chain.ts`. The addresses come from Uniswap's official
[Robinhood deployment registry](https://github.com/Uniswap/contracts/blob/main/deployments/4663.md).
Uniswap v4 and other DEX designs require their own reviewed discovery adapter before
they are included in automatic LP discovery.
