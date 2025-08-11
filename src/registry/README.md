# TokenRegistry

## Description
Precompiles like `spotBalance`, `spotPx` and more, all require either a token index (for `spotBalance`) or a spot market index (for `spotPx`) as an input parameter.

Natively, there is no way to derive the token index given a token's contract address, requiring projects to store it manually, or pass it in as a parameter whenever needed.

TokenRegistry solves this by providing a deployed-onchain mapping from EVM contract addresses to their HyperCore token indices, populated trustlessly using precompile lookups for each index.

## Usage
The `PrecompileLib` uses the `TokenRegistry`, and can be used instead of directly interacting with the `TokenRegistry` contract. 

For reference, the `TokenRegistry` is deployed on mainnet at [0x0b51d1a9098cf8a72c325003f44c194d41d7a85b](https://hyperevmscan.io/address/0x0b51d1a9098cf8a72c325003f44c194d41d7a85b)

