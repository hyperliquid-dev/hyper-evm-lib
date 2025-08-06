// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {TokenRegistry} from "../src/registry/TokenRegistry.sol";
import {console} from "forge-std/console.sol";
import {PrecompileLib} from "../src/PrecompileLib.sol";
import {Script, VmSafe} from "forge-std/Script.sol";
import {PrecompileSimulator} from "../test/utils/PrecompileSimulator.sol";

// In order for the script to work, run `forge script` with the `--skip-simulation` flag
contract PrecompileScript is Script {

    function run() public {

        vm.startBroadcast(vm.envUint("PRIV"));
        PrecompileSimulator.init(); // script works because of this

        TokenRegistry registry = TokenRegistry(0x0b51d1A9098cf8a72C325003F44C194D41d7A85B);
        registry.setTokenInfo(1);

        vm.stopBroadcast();

    }

}

