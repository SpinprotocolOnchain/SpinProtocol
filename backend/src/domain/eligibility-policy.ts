import { encodeAbiParameters, getAddress, isHex, keccak256, stringToHex, zeroAddress, type Address, type Hex } from "viem";

import type { HolderSnapshot, HolderWeight } from "./holder-snapshot.js";
import { hashCooldownExclusions } from "./winner-cooldown.js";

/** A DEX factory is only trusted after its address and adapter version are locked for the round. */
export type SupportedPoolFactory = Readonly<{
  adapterId: string;
  factory: Address;
}>;

/** Evidence decoded from the official factory's pool-creation event. */
export type DiscoveredPool = Readonly<{
  adapterId: string;
  factory: Address;
  pool: Address;
  token0: Address;
  token1: Address;
}>;

/** Historical eth_getCode result at the finalised snapshot cutoff block. */
export type AccountCodeEvidence = Readonly<{
  account: Address;
  blockHash: Hex;
  code: Hex;
}>;

export type EligibilityPolicyInput = Readonly<{
  qualificationToken: Address;
  cutoffBlockHash: Hex;
  staticExcludedAccounts: readonly Address[];
  staticExclusionListHash: Hex;
  cooldownExcludedAccounts: readonly Address[];
  cooldownExclusionListHash: Hex;
  supportedFactories: readonly SupportedPoolFactory[];
  discoveredPools: readonly DiscoveredPool[];
  accountCode: readonly AccountCodeEvidence[];
}>;

export class EligibilityPolicyValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "EligibilityPolicyValidationError";
  }
}

const EXCLUSION_LIST_DOMAIN = keccak256(stringToHex("SPIN_STATIC_EXCLUSION_LIST_V1"));

export function hashStaticExclusionList(accounts: readonly Address[]): Hex {
  const normalized = accounts.map(normalize).sort();
  if (new Set(normalized).size !== normalized.length) {
    throw new EligibilityPolicyValidationError("duplicate static exclusion address");
  }

  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "address[]" }],
      [EXCLUSION_LIST_DOMAIN, normalized.map((account) => getAddress(account))],
    ),
  );
}

/**
 * v1 is EOA-only. It excludes every address with code at the finalised cutoff,
 * which catches LP pools even if a supported factory was not indexed. Factory
 * evidence adds a second, auditable source for the explicit LP exclusion list.
 */
export function filterToEligibleEoas(
  snapshot: HolderSnapshot,
  input: EligibilityPolicyInput,
): HolderSnapshot {
  const token = normalize(input.qualificationToken);
  const poolAddresses = validatePools(input, token);

  if (hashStaticExclusionList(input.staticExcludedAccounts) !== input.staticExclusionListHash) {
    throw new EligibilityPolicyValidationError("static exclusion list does not match its commitment");
  }

  if (hashCooldownExclusions(input.cooldownExcludedAccounts) !== input.cooldownExclusionListHash) {
    throw new EligibilityPolicyValidationError("cooldown exclusions do not match their commitment");
  }

  const staticExclusions = new Set(input.staticExcludedAccounts.map(normalize));

  const cooldownExclusions = new Set(input.cooldownExcludedAccounts.map(normalize));

  if (new Set(input.cooldownExcludedAccounts.map(normalize)).size !== input.cooldownExcludedAccounts.length) {
    throw new EligibilityPolicyValidationError("duplicate cooldown exclusion address");
  }

  const codeByAccount = new Map<string, AccountCodeEvidence>();

  for (const evidence of input.accountCode) {
    const account = normalize(evidence.account);

    if (!isHex(evidence.blockHash, { strict: true }) || evidence.blockHash.length !== 66) {
      throw new EligibilityPolicyValidationError("account code evidence needs a bytes32 block hash");
    }

    if (evidence.blockHash.toLowerCase() !== input.cutoffBlockHash.toLowerCase()) {
      throw new EligibilityPolicyValidationError("account code evidence must use the snapshot cutoff block");
    }

    if (!isHex(evidence.code, { strict: true })) {
      throw new EligibilityPolicyValidationError("account code evidence is not valid hex");
    }

    if (codeByAccount.has(account)) throw new EligibilityPolicyValidationError("duplicate account code evidence");
    codeByAccount.set(account, evidence);
  }

  const holders: HolderWeight[] = [];

  let totalWeight = 0n;

  for (const holder of snapshot.holders) {
    const account = normalize(holder.account);
    const evidence = codeByAccount.get(account);

    if (evidence === undefined) {
      throw new EligibilityPolicyValidationError(`missing historical code evidence for ${holder.account}`);
    }

    if (account === zeroAddress || staticExclusions.has(account) || cooldownExclusions.has(account) || poolAddresses.has(account) || evidence.code !== "0x") continue;

    holders.push(holder);
    totalWeight += holder.weight;
  }

  return { holders, holderCount: holders.length, totalWeight };
}

function validatePools(input: EligibilityPolicyInput, qualificationToken: string): Set<string> {
  const factories = new Map<string, string>();
  for (const factory of input.supportedFactories) {
    if (!factory.adapterId) throw new EligibilityPolicyValidationError("pool adapterId is required");
    if (factories.has(factory.adapterId)) throw new EligibilityPolicyValidationError("duplicate pool adapterId");
    factories.set(factory.adapterId, normalize(factory.factory));
  }

  const pools = new Set<string>();
  for (const pool of input.discoveredPools) {
    const factory = factories.get(pool.adapterId);
    if (factory === undefined || factory !== normalize(pool.factory)) {
      throw new EligibilityPolicyValidationError("pool does not come from a supported factory adapter");
    }
    const token0 = normalize(pool.token0);
    const token1 = normalize(pool.token1);
    if (token0 !== qualificationToken && token1 !== qualificationToken) {
      throw new EligibilityPolicyValidationError("discovered pool does not contain the qualification token");
    }
    pools.add(normalize(pool.pool));
  }
  return pools;
}

function normalize(address: Address): string {
  return getAddress(address).toLowerCase();
}
