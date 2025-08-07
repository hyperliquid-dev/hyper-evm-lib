# Examples

This directory contains practical examples demonstrating how to use `evm-lib` to interact with HyperEVM and HyperCore. Each example showcases different aspects of the library's functionality.

---

## Core Concepts

### Function Overloading in Bridging
The library provides two ways to bridge tokens:
1. **By Token Address**: [bridgeToCore(address tokenAddress, uint256 evmAmount)](https://github.com/hyperliquid-dev/evm-lib/blob/f27ed9ebcba8c61c6cbfbe4727c52e50d0c2759b/src/CoreWriterLib.sol#L38-L41)
2. **By Token ID**: [bridgeToCore(uint64 token, uint256 evmAmount)](https://github.com/hyperliquid-dev/evm-lib/blob/f27ed9ebcba8c61c6cbfbe4727c52e50d0c2759b/src/CoreWriterLib.sol#L43-L53)

The address version uses the [TokenRegistry](https://github.com/hyperliquid-dev/evm-lib/blob/main/src/registry/TokenRegistry.sol) to resolve the token ID, making it more convenient for developers who work with EVM token contracts.

### Decimal Conversions
Tokens are represented using differing amounts of precision depending on where they're used:
- **EVM**
- **Spot** 
- **Perps**

The library provides conversion functions to handle these differences.

### TokenRegistry Usage
The TokenRegistry eliminates the need to manually track token IDs by providing an on-chain mapping from EVM contract addresses to HyperCore token indices. This is populated trustlessly using the precompiles

---
