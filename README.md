# SPIN PROTOCOL

[![Verify](https://github.com/SpinprotocolOnchain/SpinProtocol/actions/workflows/verify.yml/badge.svg)](https://github.com/SpinprotocolOnchain/SpinProtocol/actions/workflows/verify.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-0B6B53.svg)](LICENSE)

Read [eligible holders and LP exclusion](docs/eligibility.md) before integrating a token.
Read [how weighted odds work](docs/weighted-odds.md) for the probability formula and cooldown.

Open-source jackpot infrastructure for token communities. Projects route fee revenue
into transparent, time-weighted holder rewards with verifiable randomness and
automatic on-chain payouts.

> **Development software.** The contracts have local test coverage, but have not
> received an independent production security audit and are not deployed by this repository.

The initial EVM deployment targets Robinhood Chain and combines on-chain fee funding
with Dice Protocol randomness. The domain and application layers stay chain-neutral
so additional networks can be added without rewriting the jackpot rules. Dexch.art
data is informational only; it never determines eligibility, payouts or trading.

## Layout

```text
contracts/
  evm/
    foundry.toml
    src/{interfaces,libraries}/   Solidity contracts
    test/{unit,fuzz,invariant,mocks}/
    script/                      Solidity deployment scripts
    lib/                         Pinned Solidity dependencies
backend/
  src/
    domain/                      Jackpot rules
    application/                 Application workflows
    ports/                       External service interfaces
    adapters/
      chains/evm/                Robinhood Chain RPC and transaction handling
      randomness/dice/           Dice Protocol integration
      data/dexchart/             Dexch.art client
      persistence/               Durable state and event checkpoints
    config/                      Environment configuration
  scripts/                       Operational scripts
  test/{unit,integration,fixtures}/
config/chains/                   Robinhood Chain configuration
deployments/                     Deployment manifests
docs/architecture.md             Architecture notes
```

The backend is the npm workspace. Contracts use Foundry independently.

## Clone

OpenZeppelin Contracts is pinned as a Git submodule. Clone the repository with its
submodules, or initialize them after cloning:

```sh
git clone --recurse-submodules https://github.com/SpinprotocolOnchain/SpinProtocol.git
# Existing clone:
git submodule update --init --recursive
```

## Toolchain

- Node.js 24.20.0; npm 11.14.1
- TypeScript 5.9.3; @types/node 24.13.3
- viem 2.56.3
- Foundry 1.8.1; Solidity 0.8.36; Paris EVM; optimizer 200; via IR

Robinhood Chain is the only supported deployment today. The repository structure
keeps chain-specific code behind adapters so future networks can be added without
changing the protocol rules.

Each integrator sets the formula inputs: minimum payout, maximum winner count,
eligibility and qualification window. The vault calculates the actual winner
count and equal payout per winner from the recorded pot. Inputs lock before Dice
randomness is requested. See [the architecture](docs/architecture.md) and the
[settlement formula](docs/settlement.md). A non-technical explanation is available
in [how-it-works.md](docs/how-it-works.md). See [fairness.md](docs/fairness.md)
for the weighted-holder model and its verification limits.
Read [tokenomics.md](docs/tokenomics.md) for the immutable 97.5 / 1 / 1 / 0.5 WETH
allocation and the gated `$SPIN` buyback-and-burn design.
Read [round-lifecycle.md](docs/round-lifecycle.md) for the enforced configuration,
finality and root-review sequence.

```sh
nvm install
nvm use
npm ci
npm run typecheck
npm run chain:local
```

Anvil runs locally with test balances and no real gas. Run the Solidity suite with:

```sh
npm run contracts:build
npm run contracts:fmt
npm run contracts:test
```

Use local Dice mocks and Dexch.art fixtures for offline tests. A fork requires an
RPC provider and does not make a real Dice provider fulfill local requests.

## License

Released under the [MIT License](LICENSE).

## Security

Read [SECURITY.md](SECURITY.md) before reporting a vulnerability. Repository owners
must enable GitHub Private vulnerability reporting before public promotion.
