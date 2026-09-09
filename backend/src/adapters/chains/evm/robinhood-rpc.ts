import {
  createPublicClient,
  getAddress,
  http,
  parseAbiItem,
  type Address,
  type Hex,
  type PublicClient,
} from "viem";

import type { TokenTransfer } from "../../../domain/holder-snapshot.js";
import type { DiscoveredPool, SupportedPoolFactory } from "../../../domain/eligibility-policy.js";
import type { SettledWinner } from "../../../domain/winner-cooldown.js";
import { ROBINHOOD_SUPPORTED_POOL_FACTORIES } from "../../../config/robinhood-chain.js";
import type { SnapshotChainReader } from "../../../application/build-snapshot-artifact.js";

export const ROBINHOOD_CHAIN_ID = 4_663;

const transferEvent = parseAbiItem(
  "event Transfer(address indexed from, address indexed to, uint256 value)",
);
const pairCreatedEvent = parseAbiItem(
  "event PairCreated(address indexed token0, address indexed token1, address pair, uint256 pairCount)",
);
const poolCreatedEvent = parseAbiItem(
  "event PoolCreated(address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool)",
);
const winnerPaidEvent = parseAbiItem(
  "event WinnerPaid(uint256 indexed roundId, uint256 indexed winnerOrdinal, address indexed winner, uint256 payout, uint256 selectedWeight)",
);

export type RobinhoodRpcConfig = Readonly<{
  rpcUrl: string;
  expectedChainId?: number;
}>;

/**
 * Request boundaries are configuration, not protocol rules. A paid archive RPC
 * can safely use wider ranges; a restricted development RPC can use 10 blocks.
 */
export type RobinhoodSnapshotReaderConfig = Readonly<{
  transferBlockSpan: bigint;
  poolDiscoveryBlockSpan: bigint;
  factories?: readonly SupportedPoolFactory[];
}>;

export class RobinhoodRpcValidationError extends Error {
  public constructor(message: string) {
    super(message);
    this.name = "RobinhoodRpcValidationError";
  }
}

export function createRobinhoodPublicClient(config: RobinhoodRpcConfig): PublicClient {
  let endpoint: URL;
  try {
    endpoint = new URL(config.rpcUrl);
  } catch {
    throw new RobinhoodRpcValidationError("RPC URL is invalid");
  }
  if (endpoint.protocol !== "https:" && !(endpoint.protocol === "http:" && endpoint.hostname === "127.0.0.1")) {
    throw new RobinhoodRpcValidationError("RPC URL must use HTTPS outside local development");
  }
  const chainId = config.expectedChainId ?? ROBINHOOD_CHAIN_ID;
  if (!Number.isSafeInteger(chainId) || chainId <= 0) {
    throw new RobinhoodRpcValidationError("expected chain ID must be a positive safe integer");
  }
  return createPublicClient({
    chain: {
      id: chainId,
      name: "Robinhood Chain",
      nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
      rpcUrls: { default: { http: [config.rpcUrl] } },
    },
    transport: http(config.rpcUrl),
  });
}

export async function assertRobinhoodChain(
  client: Pick<PublicClient, "getChainId">,
  expectedChainId = ROBINHOOD_CHAIN_ID,
): Promise<void> {
  const actualChainId = await client.getChainId();
  if (actualChainId !== expectedChainId) {
    throw new RobinhoodRpcValidationError(
      `RPC chain ID ${actualChainId} does not match expected chain ID ${expectedChainId}`,
    );
  }
}

/** Reads canonical ERC-20 Transfer logs and attaches each log's block timestamp. */
export async function readTokenTransfers(
  client: PublicClient,
  input: Readonly<{ token: Address; fromBlock: bigint; toBlock: bigint }>,
): Promise<readonly TokenTransfer[]> {
  if (input.fromBlock > input.toBlock) {
    throw new RobinhoodRpcValidationError("fromBlock must not be after toBlock");
  }
  const logs = await client.getLogs({
    address: getAddress(input.token.toLowerCase()),
    event: transferEvent,
    fromBlock: input.fromBlock,
    toBlock: input.toBlock,
    strict: true,
  });
  const blocks = new Map<bigint, { hash: Hex; timestamp: bigint }>();
  const transfers: TokenTransfer[] = [];
  for (const log of logs) {
    if (log.removed || log.blockHash === null || log.blockNumber === null || log.logIndex === null) {
      throw new RobinhoodRpcValidationError("RPC returned an unmined transfer log");
    }
    if (log.blockNumber < input.fromBlock || log.blockNumber > input.toBlock) {
      throw new RobinhoodRpcValidationError("RPC returned a transfer outside the requested range");
    }
    let block = blocks.get(log.blockNumber);
    if (block === undefined) {
      block = await client.getBlock({ blockNumber: log.blockNumber });
      blocks.set(log.blockNumber, block);
    }
    if (block.hash !== log.blockHash) {
      throw new RobinhoodRpcValidationError("transfer block hash differs from canonical block");
    }
    transfers.push({
      from: log.args.from,
      to: log.args.to,
      amount: log.args.value,
      blockNumber: log.blockNumber,
      logIndex: Number(log.logIndex),
      timestamp: block.timestamp,
    });
  }
  return transfers;
}

/** Reads a large range in bounded requests, preserving canonical block/log order. */
export async function readTokenTransfersInChunks(
  client: PublicClient,
  input: Readonly<{ token: Address; fromBlock: bigint; toBlock: bigint; blockSpan: bigint }>,
): Promise<readonly TokenTransfer[]> {
  if (input.blockSpan <= 0n) {
    throw new RobinhoodRpcValidationError("blockSpan must be positive");
  }
  if (input.fromBlock > input.toBlock) {
    throw new RobinhoodRpcValidationError("fromBlock must not be after toBlock");
  }
  const transfers: TokenTransfer[] = [];
  for (let fromBlock = input.fromBlock; fromBlock <= input.toBlock; fromBlock += input.blockSpan) {
    const toBlock = min(fromBlock + input.blockSpan - 1n, input.toBlock);
    transfers.push(...await readTokenTransfers(client, { token: input.token, fromBlock, toBlock }));
  }
  return transfers;
}

export async function readBlockHash(client: PublicClient, blockNumber: bigint): Promise<Hex> {
  return (await client.getBlock({ blockNumber })).hash;
}

export async function readCodeAtBlock(
  client: PublicClient,
  account: Address,
  blockNumber: bigint,
  blockHash?: Hex,
): Promise<Hex> {
  return (await client.getCode({ address: account,
    ...(blockHash === undefined ? { blockNumber } : { blockHash, requireCanonical: true }),
  })) ?? "0x";
}

/** Reads final winner events from the exact deployed settlement-controller address. */
export async function readSettlementWinners(
  client: PublicClient,
  input: Readonly<{
    settlementController: Address;
    roundId: bigint;
    fromBlock: bigint;
    toBlock: bigint;
  }>,
): Promise<readonly SettledWinner[]> {
  if (input.fromBlock > input.toBlock) {
    throw new RobinhoodRpcValidationError("winner event range is invalid");
  }
  const logs = await client.getLogs({
    address: getAddress(input.settlementController),
    event: winnerPaidEvent,
    args: { roundId: input.roundId },
    fromBlock: input.fromBlock,
    toBlock: input.toBlock,
    strict: true,
  });
  const winners: SettledWinner[] = [];
  for (const log of logs) {
    if (log.removed || log.blockNumber === null || log.blockHash === null || log.args.winner === undefined) {
      throw new RobinhoodRpcValidationError("RPC returned a non-canonical winner event");
    }
    const block = await client.getBlock({ blockNumber: log.blockNumber });
    if (block.hash !== log.blockHash) {
      throw new RobinhoodRpcValidationError("winner event block hash differs from canonical block");
    }
    winners.push({ roundId: input.roundId, account: log.args.winner });
  }
  return winners;
}

/** Discovers direct Uniswap v2/v3 pools for a token from the verified factory events. */
export async function discoverRobinhoodUniswapPools(
  client: PublicClient,
  input: Readonly<{
    token: Address;
    fromBlock: bigint;
    toBlock: bigint;
    factories?: readonly SupportedPoolFactory[];
    blockSpan?: bigint;
  }>,
): Promise<readonly DiscoveredPool[]> {
  if (input.fromBlock > input.toBlock) {
    throw new RobinhoodRpcValidationError("fromBlock must not be after toBlock");
  }
  const blockSpan = input.blockSpan ?? input.toBlock - input.fromBlock + 1n;
  if (blockSpan <= 0n) {
    throw new RobinhoodRpcValidationError("blockSpan must be positive");
  }
  const factories = input.factories ?? ROBINHOOD_SUPPORTED_POOL_FACTORIES;
  const token = getAddress(input.token.toLowerCase());
  const pools: DiscoveredPool[] = [];
  for (let fromBlock = input.fromBlock; fromBlock <= input.toBlock; fromBlock += blockSpan) {
    const toBlock = min(fromBlock + blockSpan - 1n, input.toBlock);
    pools.push(...await discoverPoolsInRange(client, factories, token, fromBlock, toBlock));
  }
  return deduplicatePools(pools);
}

/**
 * Connects the snapshot builder to Robinhood Chain. All historical log
 * reads pass through configured bounded ranges so changing RPC providers never
 * changes the snapshot math.
 */
export function createRobinhoodSnapshotReader(
  client: PublicClient,
  config: RobinhoodSnapshotReaderConfig,
): SnapshotChainReader {
  if (config.transferBlockSpan <= 0n || config.poolDiscoveryBlockSpan <= 0n) {
    throw new RobinhoodRpcValidationError("snapshot reader block spans must be positive");
  }
  return {
    readChainId: async () => BigInt(await client.getChainId()),
    readBlockNumber: () => client.getBlockNumber(),
    readTransfers: (token, fromBlock, toBlock) => readTokenTransfersInChunks(client, {
      token,
      fromBlock,
      toBlock,
      blockSpan: config.transferBlockSpan,
    }),
    readBlockHash: (blockNumber) => readBlockHash(client, blockNumber),
    readCode: (account, blockNumber, blockHash) => readCodeAtBlock(client, account, blockNumber, blockHash),
    readSettledWinners: (settlementController, roundId, fromBlock, toBlock) =>
      readSettlementWinners(client, { settlementController, roundId, fromBlock, toBlock }),
    discoverPools: (token, fromBlock, toBlock) => discoverRobinhoodUniswapPools(client, {
      token,
      fromBlock,
      toBlock,
      blockSpan: config.poolDiscoveryBlockSpan,
      ...(config.factories === undefined ? {} : { factories: config.factories }),
    }),
  };
}

async function discoverPoolsInRange(
  client: PublicClient,
  factories: readonly SupportedPoolFactory[],
  token: Address,
  fromBlock: bigint,
  toBlock: bigint,
): Promise<readonly DiscoveredPool[]> {
  const pools: DiscoveredPool[] = [];
  for (const factory of factories) {
    if (factory.adapterId.startsWith("uniswap-v2")) {
      const logs = (await Promise.all([
        client.getLogs({ address: factory.factory, event: pairCreatedEvent, args: { token0: token }, fromBlock, toBlock, strict: true }),
        client.getLogs({ address: factory.factory, event: pairCreatedEvent, args: { token1: token }, fromBlock, toBlock, strict: true }),
      ])).flat();
      for (const log of logs) pools.push({ adapterId: factory.adapterId, factory: factory.factory, pool: log.args.pair, token0: log.args.token0, token1: log.args.token1 });
      continue;
    }
    if (factory.adapterId.startsWith("uniswap-v3")) {
      const logs = (await Promise.all([
        client.getLogs({ address: factory.factory, event: poolCreatedEvent, args: { token0: token }, fromBlock, toBlock, strict: true }),
        client.getLogs({ address: factory.factory, event: poolCreatedEvent, args: { token1: token }, fromBlock, toBlock, strict: true }),
      ])).flat();
      for (const log of logs) pools.push({ adapterId: factory.adapterId, factory: factory.factory, pool: log.args.pool, token0: log.args.token0, token1: log.args.token1 });
      continue;
    }
    throw new RobinhoodRpcValidationError(`unsupported pool adapter ${factory.adapterId}`);
  }
  return pools;
}

function deduplicatePools(pools: readonly DiscoveredPool[]): readonly DiscoveredPool[] {
  const seen = new Set<string>();
  return pools.filter((pool) => {
    const key = pool.pool.toLowerCase();
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}


function min(left: bigint, right: bigint): bigint {
  return left < right ? left : right;
}
