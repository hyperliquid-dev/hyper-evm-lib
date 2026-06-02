// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

/// @title FfiPrecompileMock
/// @notice Generic mock that forwards any call to the real chain via `cast call` FFI.
/// @dev Deploy once (baking block number into runtime bytecode as an immutable),
///      then `vm.etch` the runtime code to each precompile address.
///      Each instance uses `address(this)` as the RPC target so a single
///      bytecode works at every address.
///      Pass 0 for blockNumber to use the RPC's latest block (no --block flag).
///
///      Requirements:
///        - `ffi = true` in foundry.toml (gated under `[profile.ffi]` here)
///        - `FORK_RPC_URL` env var set (the fixture sets this in setUp)
///
///      Usage:
///        FfiPrecompileMock mock = new FfiPrecompileMock(FORK_BLOCK);  // or 0 for latest
///        bytes memory code = address(mock).code;
///        vm.etch(PRECOMPILE_ADDR, code);
contract FfiPrecompileMock {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    /// @dev Baked into runtime bytecode — preserved across vm.etch copies. If 0, calls use latest
    /// block (no --block).
    uint256 private immutable BLOCK;

    constructor(uint256 blockNumber) {
        BLOCK = blockNumber;
    }

    /// @dev Forwards msg.data to the real precompile via `cast call` and returns
    ///      the raw result. Gas metering is paused so the cheatcode overhead
    ///      doesn't count against the caller's gas cap.
    fallback() external {
        vm.pauseGasMetering();
        bytes memory result;

        if (BLOCK != 0) {
            string[] memory cmd = new string[](9);
            cmd[0] = "cast";
            cmd[1] = "call";
            cmd[2] = vm.toString(address(this)); // precompile address after etch
            cmd[3] = "--data";
            cmd[4] = vm.toString(msg.data); // raw ABI-encoded precompile input
            cmd[5] = "--rpc-url";
            cmd[6] = vm.envString("FORK_RPC_URL");
            cmd[7] = "--block";
            cmd[8] = vm.toString(BLOCK);
            result = vm.ffi(cmd);
        } else {
            string[] memory cmd = new string[](7);
            cmd[0] = "cast";
            cmd[1] = "call";
            cmd[2] = vm.toString(address(this)); // precompile address after etch
            cmd[3] = "--data";
            cmd[4] = vm.toString(msg.data); // raw ABI-encoded precompile input
            cmd[5] = "--rpc-url";
            cmd[6] = vm.envString("FORK_RPC_URL");
            result = vm.ffi(cmd);
        }

        vm.resumeGasMetering();

        assembly {
            return(add(result, 0x20), mload(result))
        }
    }
}
