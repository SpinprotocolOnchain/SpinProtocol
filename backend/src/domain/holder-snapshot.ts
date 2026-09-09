import { getAddress, zeroAddress, type Address } from "viem";

export type SnapshotWindow = Readonly<{
  startBlock: bigint;
  endBlock: bigint;
  startTimestamp: bigint;
  endTimestamp: bigint;
}>;

export type HolderBalance = Readonly<{
  account: Address;
  balance: bigint;
}>;

export type TokenTransfer = Readonly<{
  from: Address;
  to: Address;
  amount: bigint;
  blockNumber: bigint;
  logIndex: number;
  timestamp: bigint;
}>;

export type SnapshotInput = Readonly<{
  window: SnapshotWindow;
  initialBalances: readonly HolderBalance[];
  transfers: readonly TokenTransfer[];
  minimumWeight?: bigint;
}>;

export type HolderWeight = Readonly<{
  account: Address;
  weight: bigint;
}>;

export type HolderSnapshot = Readonly<{
  holders: readonly HolderWeight[];
  holderCount: number;
  totalWeight: bigint;
}>;

type AccountState = {
  balance: bigint;
  lastUpdatedAt: bigint;
  weight: bigint;
};

const ZERO_ADDRESS_KEY = zeroAddress.toLowerCase();

export class SnapshotValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "SnapshotValidationError";
  }
}

export function buildHolderSnapshot(input: SnapshotInput): HolderSnapshot {
  validateWindow(input.window);

  const minimumWeight = input.minimumWeight ?? 1n;

  if (minimumWeight < 0n) {
    throw new SnapshotValidationError("minimumWeight cannot be negative");
  }

  const accounts = new Map<string, AccountState>();

  for (const initialBalance of input.initialBalances) {
    const account = normalizeAddress(initialBalance.account);

    if (account === ZERO_ADDRESS_KEY) {
      continue;
    }

    if (initialBalance.balance < 0n) {
      throw new SnapshotValidationError("initial balances cannot be negative");
    }

    if (accounts.has(account)) {
      throw new SnapshotValidationError(`duplicate initial balance for ${account}`);
    }

    accounts.set(account, {
      balance: initialBalance.balance,
      lastUpdatedAt: input.window.startTimestamp,
      weight: 0n,
    });
  }

  let previousTransfer: TokenTransfer | undefined;

  for (const transfer of input.transfers) {
    validateTransfer(transfer, input.window, previousTransfer);
    previousTransfer = transfer;

    const from = normalizeAddress(transfer.from);
    const to = normalizeAddress(transfer.to);

    if (from === to || transfer.amount === 0n) {
      continue;
    }

    if (from !== ZERO_ADDRESS_KEY) {
      const sender = settleAccount(accounts, from, transfer.timestamp, input.window.startTimestamp);

      if (sender.balance < transfer.amount) {
        throw new SnapshotValidationError(
          `transfer exceeds tracked balance for ${from} at block ${transfer.blockNumber}`,
        );
      }

      sender.balance -= transfer.amount;
    }

    if (to !== ZERO_ADDRESS_KEY) {
      const receiver = settleAccount(accounts, to, transfer.timestamp, input.window.startTimestamp);
      receiver.balance += transfer.amount;
    }
  }

  const holders: HolderWeight[] = [];
  let totalWeight = 0n;

  for (const [account, state] of accounts) {
    settle(state, input.window.endTimestamp);

    if (
      account === ZERO_ADDRESS_KEY || state.weight < minimumWeight
    ) {
      continue;
    }

    holders.push({ account: getAddress(account), weight: state.weight });
    totalWeight += state.weight;
  }

  holders.sort((left, right) => left.account.toLowerCase().localeCompare(right.account.toLowerCase()));

  return {
    holders,
    holderCount: holders.length,
    totalWeight,
  };
}

function validateWindow(window: SnapshotWindow): void {
  if (window.startBlock > window.endBlock) {
    throw new SnapshotValidationError("startBlock must not be after endBlock");
  }

  if (window.startTimestamp >= window.endTimestamp) {
    throw new SnapshotValidationError("snapshot window must have positive duration");
  }
}

function validateTransfer(
  transfer: TokenTransfer,
  window: SnapshotWindow,
  previousTransfer: TokenTransfer | undefined,
): void {
  if (transfer.amount < 0n) {
    throw new SnapshotValidationError("transfer amount cannot be negative");
  }

  if (transfer.blockNumber < window.startBlock || transfer.blockNumber > window.endBlock) {
    throw new SnapshotValidationError("transfer is outside the snapshot block range");
  }

  if (transfer.timestamp < window.startTimestamp || transfer.timestamp > window.endTimestamp) {
    throw new SnapshotValidationError("transfer is outside the snapshot time range");
  }

  if (!Number.isSafeInteger(transfer.logIndex) || transfer.logIndex < 0) {
    throw new SnapshotValidationError("transfer logIndex must be a non-negative safe integer");
  }

  if (previousTransfer === undefined) {
    return;
  }

  const blockOrder = transfer.blockNumber - previousTransfer.blockNumber;

  if (blockOrder < 0n || (blockOrder === 0n && transfer.logIndex <= previousTransfer.logIndex)) {
    throw new SnapshotValidationError("transfers must be ordered by blockNumber and logIndex");
  }

  if (transfer.timestamp < previousTransfer.timestamp) {
    throw new SnapshotValidationError("transfer timestamps must not move backwards");
  }
}

function settleAccount(
  accounts: Map<string, AccountState>,
  account: string,
  timestamp: bigint,
  startTimestamp: bigint,
): AccountState {
  const existing = accounts.get(account);

  if (existing !== undefined) {
    settle(existing, timestamp);
    return existing;
  }

  const created: AccountState = {
    balance: 0n,
    lastUpdatedAt: startTimestamp,
    weight: 0n,
  };

  settle(created, timestamp);
  accounts.set(account, created);
  return created;
}

function settle(state: AccountState, timestamp: bigint): void {
  if (timestamp < state.lastUpdatedAt) {
    throw new SnapshotValidationError("account time cannot move backwards");
  }

  state.weight += state.balance * (timestamp - state.lastUpdatedAt);
  state.lastUpdatedAt = timestamp;
}

function normalizeAddress(account: Address): string {
  return getAddress(account).toLowerCase();
}
