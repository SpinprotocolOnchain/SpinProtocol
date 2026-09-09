// Optional until runtime validation is implemented; declarations do not validate .env.
export {};

declare global {
  namespace NodeJS {
    interface ProcessEnv {
      readonly EVM_RPC_URL?: string;
      readonly EVM_CHAIN_ID?: string;
      readonly EVM_TOKEN_DEPLOYMENT_BLOCK?: string;
      readonly DICE_CONTRACT_ADDRESS?: string;
      readonly DICE_PROVIDER_ADDRESS?: string;
      readonly DEXCHART_MODE?: string;
      readonly DEXCHART_BASE_URL?: string;
    }
  }
}
