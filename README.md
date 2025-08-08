# `evm-lib`

### **The all-in-one library to seamlessly build secure smart contracts on HyperEVM.**

This library makes it easy to build on HyperEVM. It provides a unified interface for:

* Bridging assets between HyperEVM and Core, abstracting away the complexity of decimal conversions
* Performing all `CoreWriter` actions
* Accessing data from native precompiles without needing a token index
* Obtaining token indexes, and spot market indexes based on their linked evm contract address

This library securely abstracts away the low-level mechanics of Hyperliquid's EVM ↔ Core interactions so you can focus on building your protocol's core business logic.

---

## Key Components

### CoreWriterLib

Includes functions to call `CoreWriter` actions, and also has helpers to:

* Bridge tokens to/from Core
* Convert spot token amount representation between EVM and Core (wei) decimals

### PrecompileLib

Includes functionality to query the native read precompiles. 

PrecompileLib includes additional functions to query data using EVM token addresses, removing the need to store or pass in the token/spot index. 

### TokenRegistry

Precompiles like `spotBalance`, `spotPx` and more, all require either a token index (for `spotBalance`) or a spot market index (for `spotPx`) as an input parameter.

Natively, there is no way to derive the token index given a token's contract address, requiring projects to store it manually, or pass it in as a parameter whenever needed.

TokenRegistry solves this by providing a deployed-onchain mapping from EVM contract addresses to their HyperCore token indices, populated trustlessly using precompile lookups for each index.

---

## Installation

Install with **Foundry**:

```sh
$ forge install hyperliquid-dev/hyper-evm-lib
```

Add `@hyper-evm-lib/=lib/hyper-evm-lib/` to `remappings.txt`

---

## Usage Examples

See the [examples](./src/examples/) directory for examples of how the libraries can be used in practice.

---

## Security Considerations

* `bridgeToEvm()` for non-HYPE tokens requires the contract to hold HYPE on HyperCore for gas; otherwise, the `spotSend` will fail.
* Be aware of potential precision loss in `convertEvmToCoreAmount()` when the EVM token decimals exceed Core decimals, due to integer division during downscaling.
* Ensure that contracts are deployed with complete functionality to prevent stuck assets in Core
  * For example, implementing `bridgeToCore` but not `bridgeToEvm` can lead to stuck, unretrievable assets on HyperCore
* Note that precompiles return data from the start of the block, so CoreWriter actions will not be reflected in precompile data until next call.

---

## Contributing
This library is developed and maintained by the team at [Obsidian Audits](https://github.com/ObsidianAudits):

- [0xjuaan](https://github.com/0xjuaan)
- [0xspearmint](https://github.com/0xspearmint)

For support, bug reports, or integration questions, open an [issue](https://github.com/hyperliquid-dev/hyper-evm-lib/issues) or reach out on [TG](https://t.me/juan_sec)

This library is still under active development. We welcome contributions!

Want to improve or extend functionality? Feel free to create a PR.

Help us make building on Hyperliquid as smooth and secure as possible.
