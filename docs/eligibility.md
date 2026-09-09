# Eligible holders and LP exclusion

SPIN v1 uses an EOA-only rule: a wallet is eligible only when its code at the
finalised snapshot cutoff block is empty. A normal wallet has empty code. A standard
DEX pool, vault, token contract and smart-contract wallet has code and is excluded.

This is deliberately strict. It means a standard LP pool can never appear in the
final weighted holder root, so it can never be selected or paid. It also means users
who hold through a Safe or another smart wallet are not eligible in v1. Supporting
smart wallets safely needs a separate identity and eligibility design.

## Automatic LP discovery

In addition to the EOA-only rule, the indexer discovers pools from factory events of
the DEX adapters explicitly approved for the chain. A v2-style factory emits
`PairCreated`; a v3-style factory emits `PoolCreated`. SPIN accepts a discovered
pool only when the event came from the exact locked factory and the pool contains the
qualification token. These addresses form the published LP exclusion list.

The factory list, adapter version, discovery event range and resulting pool list are
all committed in the round's calculation-version and exclusion hashes before the
qualification window begins. Every root candidate must include historical
`eth_getCode` evidence for every candidate holder at the finalised cutoff block.
Missing evidence rejects the snapshot instead of guessing.

## What this guarantees

For supported factories, the published pool list is reproducible directly from the
factory's public events. Independently, any address with code at the cutoff is
excluded. These two checks ensure a normal LP-pool contract is never eligible,
including a pool from a DEX adapter that was not found by discovery.

No system can determine the economic purpose of every externally owned address. If
someone deliberately uses an ordinary wallet as off-chain custody, the chain cannot
prove that it represents liquidity. SPIN therefore promises the precise technical
rule above: eligible recipients are EOAs with a time-weighted balance, never
contracts. It does not make an unverifiable claim about hidden off-chain ownership.

## Required backend sequence

1. Lock the factory adapters, EOA-only policy and static system-address list before the window begins.
2. Read balances from the state immediately before `startBlock`.
3. Replay every token `Transfer` log from `startBlock` through `endBlock` in canonical
   log order.
4. At a finalised cutoff block, fetch `eth_getCode(account, cutoffBlock)` for every
   weighted candidate.
5. Remove every non-empty-code account and every factory-discovered pool.
6. Build the Merkle-sum root from the remaining EOAs only, bind it to the locked
   round-configuration hash, then open the public review period.

Historical code queries use the normal EVM `eth_getCode` RPC method with a block
parameter. Providers must retain historical state for the selected cutoff.

## Sources

- [Ethereum JSON-RPC `eth_getCode`](https://ethereum.org/developers/docs/apis/json-rpc/)
- [Uniswap v2 factory source](https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol)
- [Uniswap v3 factory source](https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Factory.sol)
