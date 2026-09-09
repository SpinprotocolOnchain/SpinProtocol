import type { Address } from "viem";

import type { SupportedPoolFactory } from "../domain/eligibility-policy.js";

export const ROBINHOOD_MAINNET_CHAIN_ID = 4_663n;
export const ROBINHOOD_WETH = "0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73" as Address;

/**
 * Verified against Uniswap's Robinhood Chain deployment registry. New DEXes or
 * pool models need a dedicated reviewed adapter; do not append arbitrary addresses.
 */
export const ROBINHOOD_SUPPORTED_POOL_FACTORIES: readonly SupportedPoolFactory[] = [
  {
    adapterId: "uniswap-v2-robinhood-v1",
    factory: "0x8bceaa40b9acdfaedf85adf4ff01f5ad6517937f" as Address,
  },
  {
    adapterId: "uniswap-v3-robinhood-v1",
    factory: "0x1f7d7550b1b028f7571e69a784071f0205fd2efa" as Address,
  },
];
