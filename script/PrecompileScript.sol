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
        vm.startBroadcast();
        PrecompileSimulator.init(); // script works because of this

        Tester tester = new Tester();
        tester.logValues();

        vm.stopBroadcast();
    }
}

contract Tester {
    function logValues() public {
        console.log("msg.sender", msg.sender);
        console.log("tx.origin", tx.origin);
    }
}
