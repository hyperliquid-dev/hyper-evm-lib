// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";

Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));

library PrecompileSimulator {

    uint256 constant NUM_PRECOMPILES = 17;

    function init() internal {
        // Etch all the precompiles to their respective addresses
        for (uint160 i = 0; i < NUM_PRECOMPILES; i++) {
            address precompileAddress = address(uint160(0x0000000000000000000000000000000000000800) + i);
            vm.etch(precompileAddress, type(MockPrecompile).runtimeCode);
            vm.allowCheatcodes(precompileAddress);
        }
    }
}

contract MockPrecompile {

    fallback() external payable {
        vm.pauseGasMetering();
        bytes memory response = _makeRpcCall(address(this), msg.data);
        vm.resumeGasMetering();
        assembly {
            return(add(response, 32), mload(response))
        }
    }

    function _makeRpcCall(address target, bytes memory params) internal returns (bytes memory) {
        // Construct the JSON-RPC payload
        string memory jsonPayload =
            string.concat('[{"to":"', vm.toString(target), '","data":"', vm.toString(params), '"},"latest"]');

        // Make the RPC call
        return vm.rpc("eth_call", jsonPayload);
    }
}

