import { readFile } from "node:fs/promises";
import { getAddress, keccak256, parseAbi, type Address, type Hex } from "viem";
import { assertRobinhoodChain, createRobinhoodPublicClient } from "../src/adapters/chains/evm/robinhood-rpc.js";

type Manifest = Readonly<{ chainId: number; factory: Readonly<{ address: Address; ownerSafeOrTimelock: Address; runtimeCodeHash: Hex }>; approvedEligibilityToken: Readonly<{ address: Address; runtimeCodeHash: Hex }>; integration: Readonly<{ feeRouter: Address; vault: Address; roundBook: Address; settlementController: Address; maximumWinnerCap: number }> }>;
const factoryAbi = parseAbi(["function owner() view returns (address)", "function approvedEligibilityTokenCodeHash(address) view returns (bytes32)"]);
const vaultAbi = parseAbi(["function factory() view returns (address)", "function feeRouter() view returns (address)", "function settlementController() view returns (address)"]);
const routerAbi = parseAbi(["function vault() view returns (address)"]);
const controllerAbi = parseAbi(["function projectVault() view returns (address)"]);
const roundBookAbi = parseAbi(["function eligibilityToken() view returns (address)", "function maximumWinnerCap() view returns (uint32)"]);

async function main(): Promise<void> {
  const manifestPath = process.argv[2]; const rpcUrl = process.env.EVM_RPC_URL;
  if (manifestPath === undefined || rpcUrl === undefined) throw new Error("Provide EVM_RPC_URL and a manifest path");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8")) as Manifest;
  if (manifest.chainId !== 4_663 || manifest.integration.maximumWinnerCap !== 32) throw new Error("Unsupported chain ID or winner cap");
  const client = createRobinhoodPublicClient({ rpcUrl }); await assertRobinhoodChain(client);
  const factory = address(manifest.factory.address); const token = address(manifest.approvedEligibilityToken.address); const vault = address(manifest.integration.vault); const router = address(manifest.integration.feeRouter); const controller = address(manifest.integration.settlementController); const roundBook = address(manifest.integration.roundBook);
  await Promise.all([factory, token, vault, router, controller, roundBook].map(async (account) => { if ((await client.getCode({ address: account })) === undefined) throw new Error(`No code at ${account}`); }));
  const [factoryCode, tokenCode] = await Promise.all([client.getCode({ address: factory }), client.getCode({ address: token })]);
  if (keccak256(factoryCode!) !== manifest.factory.runtimeCodeHash || keccak256(tokenCode!) !== manifest.approvedEligibilityToken.runtimeCodeHash) throw new Error("Runtime code hash differs from manifest");
  const [owner, approvedHash, vaultFactory, vaultRouter, vaultController, routerVault, controllerVault, roundToken, cap] = await Promise.all([
    client.readContract({ address: factory, abi: factoryAbi, functionName: "owner" }), client.readContract({ address: factory, abi: factoryAbi, functionName: "approvedEligibilityTokenCodeHash", args: [token] }), client.readContract({ address: vault, abi: vaultAbi, functionName: "factory" }), client.readContract({ address: vault, abi: vaultAbi, functionName: "feeRouter" }), client.readContract({ address: vault, abi: vaultAbi, functionName: "settlementController" }), client.readContract({ address: router, abi: routerAbi, functionName: "vault" }), client.readContract({ address: controller, abi: controllerAbi, functionName: "projectVault" }), client.readContract({ address: roundBook, abi: roundBookAbi, functionName: "eligibilityToken" }), client.readContract({ address: roundBook, abi: roundBookAbi, functionName: "maximumWinnerCap" }),
  ]);
  equal(owner, manifest.factory.ownerSafeOrTimelock, "factory owner"); if (approvedHash !== manifest.approvedEligibilityToken.runtimeCodeHash) throw new Error("Token approval differs from manifest"); equal(vaultFactory, factory, "vault factory"); equal(vaultRouter, router, "vault router"); equal(vaultController, controller, "vault controller"); equal(routerVault, vault, "router vault"); equal(controllerVault, vault, "controller vault"); equal(roundToken, token, "round token"); if (cap !== 32) throw new Error("Round-book winner cap differs");
  console.log("Deployment manifest is consistent with Robinhood Chain state.");
}
function address(value: Address): Address { try { return getAddress(value); } catch { throw new Error("Manifest contains an invalid address"); } }
function equal(actual: Address, expected: Address, label: string): void { if (getAddress(actual) !== getAddress(expected)) throw new Error(`${label} differs from manifest`); }
main().catch((error: unknown) => { console.error(error instanceof Error ? error.message : error); process.exitCode = 1; });
