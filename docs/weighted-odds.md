# How weighted odds work

SPIN does not give every wallet one equal ticket. A wallet earns weight for the
amount of eligible tokens it holds and for how long it holds them during the
qualification window.

```text
wallet weight = sum of (eligible token balance × time held)
first-draw chance = wallet weight / total eligible weight
```

More exactly, for wallet `i` with weight `wᵢ` and an eligible total `W`, the
first-draw probability is `wᵢ / W`. After a winner is removed, the next draw uses
the remaining total `W' = W - wWinner`. A wallet that is still eligible then has
probability `wᵢ / W'`. This is weighted sampling without replacement: the
probability is derived from the same public weight list at every step, and a wallet
whose weight was removed has probability zero for every remaining draw.

## A concrete example

Assume a ten-day qualification window and an eligible pool of 1,000,000 tokens.

- Alice holds 50,000 eligible tokens for all ten days. Her weight is 500,000
  token-days.
- Bob buys 50,000 eligible tokens halfway through. His weight is 250,000
  token-days.

Alice held the same amount for twice as long, so she has twice Bob's chance. If no
other eligible balances change, Alice has 2/3 chance and Bob has 1/3 chance of the
first draw. A wallet only has exactly 5% first-draw chance when it owns 5% of the
**total eligible time-weight**. It is not enough to own 5% only at the final block.

The eligible pool excludes the project’s committed system wallets, contract
addresses and discovered LP pools. Therefore the denominator is eligible holder
weight, not raw token supply.

## Several winners

After a wallet wins, its weight is removed for the rest of that draw. It cannot win
twice in the same round. Each later draw uses the remaining holder weight.

## Winner cooldown

SPIN v1 adds one further equal rule: a wallet that wins round `R` is excluded from
round `R + 1`. It returns automatically in round `R + 2`, where its chance is again
calculated from its time-weighted eligible balance.

The cooldown is measured in complete rounds, not in days. This keeps it identical
for every winner and avoids arguments about timestamps, delayed automation or
variable round lengths. It must be committed before the new qualification window
starts and is derived from public, settled winner events. A project cannot choose a
different cooldown for a particular wallet.

The cooldown reduces immediate repeat wins; it does not claim to identify the same
person behind several ordinary wallets. Blockchains cannot prove that separate EOAs
have the same real-world owner. The rule is applied exactly per wallet and is fully
public.
