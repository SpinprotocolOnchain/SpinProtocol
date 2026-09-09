# Deployment manifests

Store one reviewed manifest per Robinhood Chain deployment. Record the contract
address, deployment transaction, artifact hash, source revision, compiler settings
and constructor arguments. Record the factory, round book, vault, controller,
snapshot approver, WETH, fee router, Dice oracle and Dice provider addresses, plus
the controller deployment block used by the snapshot reader. Review the factory
bytecode and verify that the vault's recorded factory and controller match the
manifest before deposits are enabled. Do not store private keys or Foundry broadcast
caches.

The factory owner must be the documented protocol multisig or timelock. Before it
creates an integration, that owner must register the exact eligibility-token address
and runtime bytecode hash. Record the approval transaction, the token policy hash
and the fixed winner cap (`32`) in the manifest. Do not approve proxy-upgradeable,
rebasing, reflection, taxed or blacklisting tokens for v1.

Use `robinhood-mainnet.template.json` as the private reviewed manifest for a first
deployment. Before preparing any Safe transaction, run:

```sh
sh contracts/evm/script/preflight-robinhood-deployment.sh
```

The preflight verifies chain ID 4663 and rejects an EOA used as factory owner,
snapshot approver or eligibility token. It prints the token's runtime bytecode hash
for the approval record; compare it with the independently reviewed value before
submitting the Safe transaction.

After deployment, replace manifest placeholders and validate on-chain code hashes
and immutable links with `EVM_RPC_URL=... npm --prefix backend run deployment:validate -- ../deployments/your-manifest.json`.
