# SPIN v1 tokenomics and buyback policy

This document defines the only fee policy planned for SPIN v1. It is a protocol
rule, not a backend setting, not a dashboard preference and not a promise about
the market price of `$SPIN`.

## One incoming deposit, four destinations

Every accepted WETH deposit from an integrator's linked fee-router is allocated at
the moment it enters the protocol:

```text
gross WETH deposit
  97.50% → that integrator's project jackpot
   1.00% → creator treasury
   1.00% → SPIN-holder WETH jackpot
   0.50% → SPIN buyback reserve
```

The first three destinations are independent pots. Money sent to a project jackpot
cannot later fund `$SPIN`, the creator treasury, a buyback or another project.
Likewise, creator and buyback money can never lower a payout that was already
credited to a project jackpot.

The exact basis-point policy is immutable in the initial factory:

| Destination | Basis points | Share |
| --- | ---: | ---: |
| Integrator project jackpot | 9,750 | 97.50% |
| Creator treasury | 100 | 1.00% |
| `$SPIN` holder jackpot | 100 | 1.00% |
| `$SPIN` buyback reserve | 50 | 0.50% |
| Total | 10,000 | 100.00% |

Integer division may leave a few wei. Those wei remain in the integrator's project
jackpot. No rounding dust is silently assigned to the creator.

## What `$SPIN` actually does

`$SPIN` has two protocol utilities, both visible on-chain:

1. Its holders are eligible for the separate `$SPIN` WETH jackpot. Odds use the
   same time-weighted holder formula as every other SPIN integration.
2. Its supply can be reduced only by the buyback-and-burn module described below.

Holding `$SPIN` does not create a fixed return, a redemption right, ownership of an
integrator's jackpot, or a claim on the creator treasury. A holder may win a WETH
jackpot according to the published weighted draw rules; a win is never guaranteed.

## Creator treasury

The creator treasury receives exactly 1.00% of each accepted deposit. It is the
protocol's disclosed revenue and covers servers, monitoring, development and the
creator's operating income. It is paid to the immutable treasury address declared
when the factory is deployed.

Changing that address later must require a public timelock and a two-step ownership
transfer. It must never be a hidden backend environment variable.

## Buyback and burn: economic rule versus execution rule

The 0.50% allocation is a **WETH reserve**, not an immediate swap. It begins
accumulating from launch, but its execution module remains paused until `$SPIN` has
an audited token contract and a reviewed, immutable `$SPIN`/WETH pool configuration.

When activated, the module may do only this:

```text
WETH buyback reserve
→ fixed $SPIN/WETH pool
→ receive $SPIN
→ call $SPIN.burn(received amount)
```

It cannot select another token, trade through a route chosen by a backend, borrow,
use leverage, retain purchased `$SPIN`, or send purchased tokens to the creator.
The `$SPIN` token must expose a real `burn(uint256)` function so `totalSupply` falls
on-chain. Sending tokens to a dead address alone is not enough because it does not
necessarily reduce total supply.

## Buyback execution guardrails

The buyback contract must enforce all of these rules before it can be activated:

- one immutable router and one immutable `$SPIN`/WETH pool;
- a reviewed quote adapter using a sufficiently long pool TWAP;
- a maximum WETH spend per epoch and a minimum delay between epochs;
- a minimum received `$SPIN` amount derived from the TWAP and a locked maximum
  slippage; a caller cannot supply `minOut = 0`;
- a minimum pool-liquidity threshold before any buy can execute;
- a permissionless execution function: anyone may trigger an already-valid buy;
- an event with WETH spent, `$SPIN` received, `$SPIN` burned, quote and epoch;
- a pause before launch, with a timelocked public activation; and
- no emergency function that can redirect reserve WETH to the creator.

The contract must skip an epoch if the price guard, liquidity guard or swap quote is
invalid. Skipping is safer than forcing a bad purchase. Unspent reserve WETH remains
accounted for the next valid epoch.

## What Dexch.art may and may not do

Dexch.art may show `$SPIN` charts, liquidity and token information in the interface.
It is not an oracle. It never chooses a pool, price, trade route, buyback timing,
winner, holder list or payout. Settlement only uses verified on-chain state.

## Launch gates

The buyback contract cannot be deployed as active until all conditions below are
met:

1. `$SPIN` has a published supply policy and a tested `burn` implementation.
2. The canonical `$SPIN`/WETH pool and router are locked in deployment metadata.
3. TWAP, liquidity and slippage limits have Foundry unit, fuzz and fork tests.
4. The WETH reserve, project jackpot and `$SPIN` jackpot have separate accounting.
5. An independent smart-contract audit covers the swap path and token contract.
6. Public token documentation states the fee flow and risks without promising price
   appreciation or a return.

EU rules include market-abuse provisions for crypto-assets admitted to trading.
The token launch, disclosures and buyback communications need qualified legal review
before a public offer or trading campaign. See [MiCA](https://eur-lex.europa.eu/eli/reg/2023/1114/oj) and the
[Belgian FSMA white-paper procedure](https://www.fsma.be/sites/default/files/media/files/2026-01/fsma_2026_02_en.pdf).
