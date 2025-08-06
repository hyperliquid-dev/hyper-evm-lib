# `evm-lib`

---

## Table of Contents

- [`evm-lib`](#evm-lib)
  - [Table of Contents](#table-of-contents)
  - [What is evm-lib?](#what-is-evm-lib)
  - [Key Components](#key-components)
    - [CoreWriterLib](#corewriterlib)
    - [PrecompileLib](#precompilelib)
    - [TokenRegistry](#tokenregistry)
  - [Usage Examples](#usage-examples)
  - [Security Considerations](#security-considerations)
  - [Contributing](#contributing)

---

## What is evm-lib?

`evm-lib` is a developer library making it easy to build on HyperEVM. It provides a unified interface for:

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

Natively, there is no way to derive the token index given a token's contract address, requiring it to be stored manually, or passed in as a parameter whenever needed.

TokenRegistry is a deployed contract providing a mapping from EVM contract addresses to their HyperCore token indices, populated trustlessly using precompile lookups for each index.

---

## Usage Examples

See the [examples](./src/examples/) directory for examples of how the libraries can be used in practice.

---

## Security Considerations

* `bridgeToEvm()` for non-HYPE tokens requires the contract to hold HYPE on HyperCore for gas; otherwise, the `spotSend` will fail.
* Watch for truncation in `convertEvmToCoreAmount()`
* Ensure that contracts are deployed with complete functionality to prevent stuck assets in Core
  * For example, implementing `bridgeToCore` but not `bridgeToEvm` can lead to stuck funds
* Note that precompiles return data from the start of the block, so CoreWriter actions will not be reflected in precompile data until next call

---

## Contributing
This library is still under active development. We welcome contributions!

Found a bug? [Open an issue](https://github.com/hyperliquid-dev/evm-lib/issues).

Want to improve or extend functionality? Feel free to create a PR.

Help us make building on Hyperliquid as smooth and secure as possible.
