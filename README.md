# hyper-evm-lib
![License](https://img.shields.io/github/license/hyperliquid-dev/hyper-evm-lib)
![Solidity](https://img.shields.io/badge/solidity-%3E%3D0.8.0-blue)

<img width="900" height="450" alt="Untitled design (2)" src="https://github.com/user-attachments/assets/6c74dc59-baff-4f6a-9dab-3b92d0cfa133" />

## The all-in-one toolkit to seamlessly build smart contracts on HyperEVM

This library makes it easy to build on HyperEVM. It provides a unified interface for:

* Bridging assets between HyperEVM and Core, abstracting away the complexity of decimal conversions
* Performing all `CoreWriter` actions
* Accessing data from native precompiles without needing a token index
* Retrieving token indexes, and spot market indexes based on their linked evm contract address

The library securely abstracts away the low-level mechanics of Hyperliquid's EVM ↔ Core interactions so you can focus on building your protocol's core business logic.

The testing framework provides a robust simulation engine for HyperCore interactions, enabling local foundry testing of precompile calls, CoreWriter actions, and EVM⇄Core token bridging. This allows developers to test their contracts in a local environment, within seconds, without needing to spend hours deploying and testing on testnet.

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

[TokenRegistry](https://github.com/hyperliquid-dev/hyper-evm-lib/blob/main/src/registry/TokenRegistry.sol) solves this by providing a deployed-onchain mapping from EVM contract addresses to their HyperCore token indices, populated trustlessly using precompile lookups for each index.

### Testing Framework

A robust and flexible simulation engine for HyperCore interactions, enabling local foundry testing of precompile calls, CoreWriter actions, and EVM⇄Core token bridging. This allows developers to test their contracts in a local environment, within seconds, without needing to spend hours deploying and testing on testnet.

For more information on usage and how it works, see the docs: [https://hyperlib.vercel.app/](https://hyperlib.vercel.app/).

---

## Installation

Install with **Foundry**:

```sh
forge install hyperliquid-dev/hyper-evm-lib
echo "@hyper-evm-lib=lib/hyper-evm-lib" >> remappings.txt
```
---

## Usage Examples

See the [examples](./src/examples/) directory for examples of how the libraries can be used in practice.

To see how the testing framework can be used, refer to [`CoreSimulatorTest.t.sol`](./test/CoreSimulatorTest.t.sol) and the testing framework docs at [https://hyperlib.vercel.app/](https://hyperlib.vercel.app/).

---

## Security Considerations

* `bridgeToEvm()` for non-HYPE tokens requires the contract to hold HYPE on HyperCore for gas; otherwise, the `spotSend` will fail.
* Be aware of potential precision loss in `evmToWei()` when the EVM token decimals exceed Core decimals, due to integer division during downscaling.
* Ensure that contracts are deployed with complete functionality to prevent stuck assets in Core
  * For example, implementing `bridgeToCore` but not `bridgeToEvm` can lead to stuck, unretrievable assets on HyperCore
* Note that precompiles return data from the start of the block, so CoreWriter actions will not be reflected in precompile data until next call.

---

## Contributing
This toolkit is developed and maintained by the team at [Obsidian Audits](https://github.com/ObsidianAudits):

- [0xjuaan](https://github.com/0xjuaan)
- [0xSpearmint](https://github.com/0xspearmint)

For support, bug reports, or integration questions, open an [issue](https://github.com/hyperliquid-dev/hyper-evm-lib/issues) or reach out on [TG](https://t.me/juan_sec)

The library and testing framework are under active development, and contributions are welcome.

Want to improve or extend functionality? Feel free to create a PR.

Help us make building on Hyperliquid as smooth and secure as possible.
