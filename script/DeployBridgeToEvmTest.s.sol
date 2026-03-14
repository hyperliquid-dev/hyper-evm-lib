// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, console} from "forge-std/Script.sol";
import {BridgeToEvmTest} from "../src/examples/BridgeToEvmTest.sol";

contract DeployBridgeToEvmTest is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy with 0.01 HYPE so contract has funds to bridge
        BridgeToEvmTest testContract = new BridgeToEvmTest{value: 0.01 ether}();

        console.log("BridgeToEvmTest deployed at:", address(testContract));
        console.log("Owner:", testContract.owner());

        vm.stopBroadcast();
    }
}

contract BridgeHypeToCore is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address contractAddr = vm.envAddress("CONTRACT");

        vm.startBroadcast(deployerPrivateKey);

        BridgeToEvmTest testContract = BridgeToEvmTest(payable(contractAddr));

        // Bridge 0.01 HYPE to Core (token index 150)
        testContract.bridgeToCore{value: 0.01 ether}(150, 0.01 ether);

        console.log("Bridged 0.01 HYPE to Core");

        vm.stopBroadcast();
    }
}

contract BridgeHypeToEvm is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address contractAddr = vm.envAddress("CONTRACT");

        vm.startBroadcast(deployerPrivateKey);

        BridgeToEvmTest testContract = BridgeToEvmTest(payable(contractAddr));

        // Bridge 0.01 HYPE back to EVM
        testContract.bridgeToEvm(150, 0.01 ether);

        console.log("Bridged 0.01 HYPE back to EVM");

        vm.stopBroadcast();
    }
}

contract WithdrawFunds is Script {
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address contractAddr = vm.envAddress("CONTRACT");

        vm.startBroadcast(deployerPrivateKey);

        BridgeToEvmTest testContract = BridgeToEvmTest(payable(contractAddr));

        // Withdraw all ETH/HYPE back to owner
        testContract.withdrawETH();

        console.log("Withdrawn all HYPE to owner");

        vm.stopBroadcast();
    }
}
