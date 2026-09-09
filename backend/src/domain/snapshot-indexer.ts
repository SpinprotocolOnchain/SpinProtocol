import { getAddress, zeroAddress, type Address } from "viem";

import {
  type HolderBalance,
  type SnapshotInput,
  type TokenTransfer,
} from "./holder-snapshot.js";

export class SnapshotIndexerValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "SnapshotIndexerValidationError";
  }
}

/**
 * Reconstructs the exact balances immediately before `startBlock`. The caller
 * supplies every Transfer log from the token deployment block through
 * `startBlock - 1`; this avoids reading a post-start-block balance and applying
 * the same block's transfers a second time.
 */
export function deriveBalancesBeforeWindow(
  transfersBeforeWindow: readonly TokenTransfer[],
  startBlock: bigint,
): readonly HolderBalance[] {
  const balances = new Map<string, bigint>();
  let previous: TokenTransfer | undefined;

  for (const transfer of transfersBeforeWindow) {
    if (transfer.blockNumber >= startBlock) {
      throw new SnapshotIndexerValidationError("pre-window transfers must end before startBlock");
    }
    validateCanonicalTransfer(transfer, previous);
    previous = transfer;

    if (transfer.amount < 0n) throw new SnapshotIndexerValidationError("transfer amount cannot be negative");
    if (transfer.amount === 0n || transfer.from === transfer.to) continue;

    const from = normalize(transfer.from);
    const to = normalize(transfer.to);
    if (from !== zeroAddress) {
      const senderBalance = balances.get(from) ?? 0n;
      if (senderBalance < transfer.amount) {
        throw new SnapshotIndexerValidationError(`unreconciled historical transfer from ${from}`);
      }
      balances.set(from, senderBalance - transfer.amount);
    }
    if (to !== zeroAddress) balances.set(to, (balances.get(to) ?? 0n) + transfer.amount);
  }

  return [...balances]
    .filter(([, balance]) => balance > 0n)
    .map(([account, balance]) => ({ account: getAddress(account), balance }))
    .sort((left, right) => left.account.toLowerCase().localeCompare(right.account.toLowerCase()));
}

/** Creates the only accepted input shape for the time-weight calculator. */
export function createIndexedSnapshotInput(input: Readonly<{
  snapshot: Omit<SnapshotInput, "initialBalances">;
  transfersBeforeWindow: readonly TokenTransfer[];
}>): SnapshotInput {
  return {
    ...input.snapshot,
    initialBalances: deriveBalancesBeforeWindow(
      input.transfersBeforeWindow,
      input.snapshot.window.startBlock,
    ),
  };
}

function validateCanonicalTransfer(current: TokenTransfer, previous: TokenTransfer | undefined): void {
  if (!Number.isSafeInteger(current.logIndex) || current.logIndex < 0) {
    throw new SnapshotIndexerValidationError("transfer logIndex must be a non-negative safe integer");
  }
  if (previous === undefined) return;
  if (
    current.blockNumber < previous.blockNumber ||
    (current.blockNumber === previous.blockNumber && current.logIndex <= previous.logIndex)
  ) {
    throw new SnapshotIndexerValidationError("transfers must be in canonical block and log order");
  }
}

function normalize(account: Address): string {
  return getAddress(account).toLowerCase();
}
