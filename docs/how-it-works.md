# How SPIN works

SPIN is a jackpot wrapper for projects on Robinhood Chain. A project links its token
address and existing fee flow once. SPIN then reads that token's public blockchain
activity and runs the jackpot automatically.

## 1. Fees enter the jackpot

The project's fee-router sends WETH to the SPIN vault. The router is not inside the
vault: it is the project's existing fee wallet or fee contract calling the vault's
deposit function. At that moment the immutable SPIN protocol split sends 97.5% to
that project's jackpot, 1% to the creator treasury, 1% to the separate `$SPIN`
holder jackpot and 0.5% to the `$SPIN` buyback reserve.

The vault cannot pull money from a fee wallet. The project must explicitly send or
approve each deposit. Every accepted deposit is recorded for the active round.

```text
trading fees → project fee-router → fixed four-way allocation
                                    → 97.5% project jackpot → next project round
```

## 2. A project sets its jackpot rules

Before a round starts, the project chooses inputs such as:

- the minimum payout worth running a draw for;
- the maximum number of winners;
- who may participate;
- the qualification window used to calculate holder weight.

Those inputs are sealed together before the window starts. The seal also includes
the token, fee-router, WETH address, exclusions and calculation version. Changing
any one of them produces a different seal, so the project cannot quietly change a
round's rules after holders have started qualifying.

The vault then calculates the actual number of winners from the pot. If there is
not enough WETH for one valid payout, nothing is drawn and the pot continues to grow.

The developer never uploads or manually selects a holder list.

## 3. Chances follow eligible ownership

SPIN does not give every holder the same chance. A holder's chance follows their
share of the eligible holdings during the qualification period.

If the eligible holder pool has a total weight of 1,000,000 and a wallet has a
weight of 50,000, that wallet has exactly 5% chance to receive the first payout.
A wallet with a weight of 10 has 0.001% chance. The denominator is the eligible
holder pool, not necessarily the token's total supply: excluded wallets and tokens
outside the published qualification rule are not counted.

See [how weighted odds work](weighted-odds.md) for the full formula and a concrete
ten-day example.

For the first release, a holder can win once per round. Each subsequent winner is
selected from the remaining eligible weight, so the same wallet cannot receive two
payouts in the same round. The winner count can never exceed the number of eligible
holders.

Each winner is excluded from the following complete round, then returns
automatically in the round after that. The one-round cooldown is identical for
everyone and is fixed before the next qualification window starts.

## 4. SPIN builds the holder snapshot automatically

At each fixed round cutoff, SPIN reads every public transfer of the linked token and
builds the holder snapshot automatically. It starts from the balance at the beginning
of the qualification window and updates balances from every transfer until the cutoff.
The developer does not provide this list and cannot pick wallets one by one.

To resist someone borrowing tokens briefly for a larger chance, SPIN uses a
time-weighted balance across the qualification window, rather than a balance at one
single block.

In plain terms: holding 5% of the eligible supply for the full window gives about
5% of the total weight. Buying 5% for only a few minutes gives only the weight for
those minutes. The exact time-weight formula, start block and end block are public.

SPIN turns the result into a Merkle-sum root: a compact cryptographic seal that
contains both each wallet's weight and the total eligible weight.

The root is submitted to the vault before the draw. The full list and calculation
details are published automatically. Anyone may check their own wallet, but no
holder action is required for the jackpot to continue. The project cannot change the
sealed list after it is locked.

The published result also seals the exact list of wallets temporarily excluded by
the one-round winner cooldown. That list is derived from the publicly settled prior
round, then hashed into the snapshot manifest. Nobody can quietly add or remove a
wallet from that cooldown after the snapshot is published.

The window itself is fixed before it starts: token, start block, end block,
exclusions and calculation method are all stored as a commitment. The backend then
replays every token transfer in that exact range. It cannot pick a different
snapshot moment after seeing which wallets would benefit.

The backend builds this root because a smart contract cannot safely scan every holder
of a token itself. A Merkle-sum proof lets the vault verify that a selected wallet
occupies the precise random interval in the sealed weighted list. Anyone with the
published data can submit the proof if SPIN automation is offline.

## 5. SPIN calculates whether to draw

The vault reserves the exact Dice fee and calculates how many payouts the remaining
project pot can support. It also limits this by
the number of eligible holders.

```text
winner count = the smallest of:
  maximum winners chosen by the project
  what the pot can pay at the minimum payout
  the number of eligible holders
```

If that result is zero, the round rolls over. If it is five, exactly five unique
holders are selected from the weighted holder list.

## 6. Dice selects the winners

Once the round is locked, the vault requests a random word from Dice Protocol. That
random word selects a precise interval inside the total eligible weight. The holder
whose weight owns that interval wins. The winner's weight is then removed before
the next draw, making every winner unique. The project, SPIN backend and players
cannot choose a different winner after the request.

## 7. Winners are paid automatically

After Dice returns the random word, SPIN automation submits the selected holder's
Merkle-sum proof to the vault. The vault verifies the proof and sends WETH directly
to the selected wallet in that same transaction. The automation wallet never receives
the prize and cannot change the recipient or amount.

Smart contracts cannot wake themselves up, so an external transaction is always
required after Dice responds. If SPIN automation is offline, anyone can submit the
same public proof and trigger the same payout. The winner never needs to claim.

## What SPIN does not do

SPIN does not hold player private keys, pull money from project wallets, trade on
behalf of the jackpot, promise token price growth or use Dexch.art data to decide a
winner or payout.
