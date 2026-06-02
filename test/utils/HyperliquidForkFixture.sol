// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {FfiPrecompileMock} from "./FfiPrecompileMock.sol";

/// @title HyperliquidForkFixture
/// @notice Test fixture library that makes HyperEVM precompiles work end-to-end in
///         Foundry fork tests.
/// @dev Creates a fork, deploys an FFI-based mock, and etches it to every read
///      precompile address (0x0800-0x0813). The mock proxies each staticcall to
///      the real chain via `cast call`, so capped staticcalls in `PrecompileLib`
///      are exercised against real precompile output.
///
///      Usage:
///        import {HyperliquidForkFixture} from "../utils/HyperliquidForkFixture.sol";
///
///        contract MyForkTest is Test {
///            function setUp() public {
///                HyperliquidForkFixture.setUp(BLOCK);          // mainnet, pinned
///                // or HyperliquidForkFixture.setUp(RPC, BLOCK);
///                // or HyperliquidForkFixture.setUpLatest();   // mainnet, latest
///            }
///        }
///
///      Requirements:
///        - `ffi = true` in foundry.toml (scoped under `[profile.ffi]` here)
///        - `cast` in PATH (standard Foundry install)
library HyperliquidForkFixture {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    string constant MAINNET_RPC = "https://rpc.hyperliquid.xyz/evm";
    string constant TESTNET_RPC = "https://rpc.hyperliquid-testnet.xyz/evm";

    uint256 constant FIRST_PRECOMPILE = 0x0800;
    uint256 constant LAST_PRECOMPILE = 0x0813;

    /// @notice Set up a fork against HyperEVM mainnet at the given block.
    /// @param blockNumber Block to pin the fork to. 0 = latest.
    function setUp(uint256 blockNumber) internal {
        setUp(MAINNET_RPC, blockNumber);
    }

    /// @notice Set up a fork against HyperEVM mainnet at the latest block.
    function setUpLatest() internal {
        setUp(MAINNET_RPC, 0);
    }

    /// @notice Set up a fork against a custom RPC at the given block.
    /// @param rpcUrl RPC endpoint URL.
    /// @param blockNumber Block to pin the fork to. 0 = latest.
    function setUp(string memory rpcUrl, uint256 blockNumber) internal {
        if (blockNumber > 0) {
            vm.createSelectFork(rpcUrl, blockNumber);
        } else {
            vm.createSelectFork(rpcUrl);
        }
        vm.setEnv("FORK_RPC_URL", rpcUrl);

        FfiPrecompileMock mock = new FfiPrecompileMock(blockNumber);
        bytes memory mockCode = address(mock).code;

        for (uint256 i = FIRST_PRECOMPILE; i <= LAST_PRECOMPILE; i++) {
            address addr = address(uint160(i));
            vm.etch(addr, mockCode);
            vm.allowCheatcodes(addr);
        }
    }
}
