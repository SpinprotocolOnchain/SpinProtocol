import { encodeAbiParameters, getAddress, keccak256, stringToHex, type Address, type Hex } from "viem";

export const WINNER_COOLDOWN_ROUNDS = 1n;

export type SettledWinner = Readonly<{
  roundId: bigint;
  account: Address;
}>;

const COOLDOWN_LIST_DOMAIN = keccak256(stringToHex("SPIN_WINNER_COOLDOWN_LIST_V1"));

/** Winners of the immediately preceding settled round cannot qualify again yet. */
export function deriveCooldownExclusions(
  roundId: bigint,
  winners: readonly SettledWinner[],
): readonly Address[] {
  if (roundId < 0n) throw new Error("roundId cannot be negative");

  const excluded = winners
    .filter((winner) => winner.roundId === roundId - WINNER_COOLDOWN_ROUNDS)
    .map((winner) => getAddress(winner.account))
    .sort((left, right) => left.toLowerCase().localeCompare(right.toLowerCase()));
  if (new Set(excluded.map((account) => account.toLowerCase())).size !== excluded.length) {
    throw new Error("winner history contains duplicate accounts in the cooldown window");
  }
  return excluded;
}

export function hashCooldownExclusions(accounts: readonly Address[]): Hex {
  const normalized = accounts.map((account) => getAddress(account)).sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));

  if (new Set(normalized.map((account) => account.toLowerCase())).size !== normalized.length) {
    throw new Error("duplicate cooldown exclusion address");
  }

  return keccak256(encodeAbiParameters([{ type: "bytes32" }, { type: "address[]" }], [COOLDOWN_LIST_DOMAIN, normalized]));
}
