import {
  encodeAbiParameters,
  getAddress,
  isHex,
  keccak256,
  stringToHex,
  zeroAddress,
  type Address,
  type Hex,
} from "viem";

import type { SnapshotWindow } from "./holder-snapshot.js";

const ROUND_CONFIGURATION_DOMAIN = keccak256(stringToHex("SPIN_ROUND_CONFIGURATION_V1"));

/** Values the factory will later make immutable before a round starts. */
export type RoundConfigurationInput = Readonly<{
  chainId: bigint;
  roundId: bigint;
  qualificationToken: Address;
  feeRouter: Address;
  settlementAsset: Address;
  window: SnapshotWindow;
  finalityBlocks: bigint;
  reviewBlocks: bigint;
  minimumPayout: bigint;
  minimumEligibleWeight: bigint;
  maximumWinners: number;
  exclusionListHash: Hex;
  calculationVersionHash: Hex;
}>;

/** Hard caps selected by the immutable factory deployment. */
export type RoundConfigurationLimits = Readonly<{
  maximumWinners: number;
}>;

export type RoundConfiguration = Readonly<{
  chainId: bigint;
  roundId: bigint;
  qualificationToken: Address;
  feeRouter: Address;
  settlementAsset: Address;
  window: SnapshotWindow;
  finalityBlocks: bigint;
  reviewBlocks: bigint;
  minimumPayout: bigint;
  minimumEligibleWeight: bigint;
  maximumWinners: number;
  exclusionListHash: Hex;
  calculationVersionHash: Hex;
  configurationHash: Hex;
}>;

export class RoundConfigurationValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "RoundConfigurationValidationError";
  }
}

/** Produces the commitment the later snapshot must reference. */
export function createRoundConfiguration(
  input: RoundConfigurationInput,
  limits: RoundConfigurationLimits,
): RoundConfiguration {
  validate(input, limits);

  const configuration: Omit<RoundConfiguration, "configurationHash"> = {
    ...input,
    qualificationToken: getAddress(input.qualificationToken),
    feeRouter: getAddress(input.feeRouter),
    settlementAsset: getAddress(input.settlementAsset),
  };

  return { ...configuration, configurationHash: hashConfiguration(configuration) };
}

function validate(input: RoundConfigurationInput, limits: RoundConfigurationLimits): void {
  if (input.chainId <= 0n) throw new RoundConfigurationValidationError("chainId must be positive");
  if (input.roundId < 0n) throw new RoundConfigurationValidationError("roundId cannot be negative");

  for (const address of [input.qualificationToken, input.feeRouter, input.settlementAsset]) {
    const normalized = getAddress(address);
    if (normalized.toLowerCase() === zeroAddress) {
      throw new RoundConfigurationValidationError("round addresses cannot be the zero address");
    }
  }

  if (input.window.startBlock >= input.window.endBlock) {
    throw new RoundConfigurationValidationError("qualification window must span at least two blocks");
  }
  if (input.window.startTimestamp >= input.window.endTimestamp) {
    throw new RoundConfigurationValidationError("qualification window must have positive duration");
  }
  if (input.finalityBlocks < 0n || input.reviewBlocks < 0n) {
    throw new RoundConfigurationValidationError("block delays cannot be negative");
  }
  if (input.minimumPayout <= 0n) {
    throw new RoundConfigurationValidationError("minimumPayout must be positive");
  }
  if (input.minimumEligibleWeight <= 0n) {
    throw new RoundConfigurationValidationError("minimumEligibleWeight must be positive");
  }

  validateWholeNumber(input.maximumWinners, "maximumWinners");
  validateWholeNumber(limits.maximumWinners, "maximumWinners limit");
  if (input.maximumWinners < 1 || input.maximumWinners > limits.maximumWinners) {
    throw new RoundConfigurationValidationError("maximumWinners is outside the factory safety cap");
  }

  for (const hash of [input.exclusionListHash, input.calculationVersionHash]) {
    if (!isHex(hash, { strict: true }) || hash.length !== 66) {
      throw new RoundConfigurationValidationError("configuration hashes must be bytes32 values");
    }
  }
}

function validateWholeNumber(value: number, name: string): void {
  if (!Number.isSafeInteger(value)) {
    throw new RoundConfigurationValidationError(`${name} must be a safe integer`);
  }
}

function hashConfiguration(configuration: Omit<RoundConfiguration, "configurationHash">): Hex {
  return keccak256(
    encodeAbiParameters(
      [
        { type: "bytes32" }, { type: "uint256" }, { type: "uint256" },
        { type: "address" }, { type: "address" }, { type: "address" },
        { type: "uint256" }, { type: "uint256" }, { type: "uint256" },
        { type: "uint256" }, { type: "uint256" }, { type: "uint256" },
        { type: "uint256" }, { type: "uint256" }, { type: "uint16" }, { type: "bytes32" }, { type: "bytes32" },
      ],
      [
        ROUND_CONFIGURATION_DOMAIN, configuration.chainId, configuration.roundId,
        configuration.qualificationToken, configuration.feeRouter, configuration.settlementAsset,
        configuration.window.startBlock, configuration.window.endBlock,
        configuration.window.startTimestamp, configuration.window.endTimestamp,
        configuration.finalityBlocks, configuration.reviewBlocks, configuration.minimumPayout, configuration.minimumEligibleWeight,
        configuration.maximumWinners, configuration.exclusionListHash, configuration.calculationVersionHash,
      ],
    ),
  );
}
