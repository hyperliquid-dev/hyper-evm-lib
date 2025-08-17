// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../src/PrecompileLib.sol";
import {HLConstants} from "../src/common/HLConstants.sol";
import {BridgingExample} from "../src/examples/BridgingExample.sol";
import {HyperCoreState} from "./simulation/HyperCoreState.sol";
import {L1Read} from "./utils/L1Read.sol";

import {CoreSimulatorLib} from "./simulation/CoreSimulatorLib.sol";

contract CoreSimulatorTest is Test {

    using PrecompileLib for address;

    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant uBTC  = 0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463;
    address public constant uETH  = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907;
    address public constant uSOL  = 0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29;

    HyperCoreState public hyperCore;
    address public user = makeAddr("user");

    BridgingExample public bridgingExample;

    L1Read l1Read;

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");

        // set up the HyperCore simulation
        hyperCore = CoreSimulatorLib.init();

        bridgingExample = new BridgingExample();

        hyperCore.forceAccountCreation(user);
        hyperCore.forceAccountCreation(address(bridgingExample));

        l1Read = new L1Read();
    }

    function test_bridgeHypeToCore() public {

        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreById{value: 1e18}(150, 1e18);

        

        (uint64 total,uint64 hold,uint64 entryNtl) = abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) = abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);
        
    }
    function test_bridgeToCoreAndSend() public {

        deal(address(user), 10000e18);

        vm.startPrank(user);
        bridgingExample.bridgeToCoreAndSendHype{value: 1e18}(1e18, address(user));


        (uint64 total,uint64 hold,uint64 entryNtl) = abi.decode(abi.encode(hyperCore.readSpotBalance(address(user), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) = abi.decode(abi.encode(hyperCore.readSpotBalance(address(user), 150)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);

    }

    function test_bridgeEthToCore() public {
        deal(address(uETH), address(bridgingExample), 1e18);

        bridgingExample.bridgeToCoreById(221, 1e18);

        (uint64 total,uint64 hold,uint64 entryNtl) = abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 221)), (uint64, uint64, uint64));
        console.log("total", total);

        CoreSimulatorLib.nextBlock();

        (total, hold, entryNtl) = abi.decode(abi.encode(hyperCore.readSpotBalance(address(bridgingExample), 221)), (uint64, uint64, uint64));
        console.log("total", total);
        console.log("hold", hold);
        console.log("entryNtl", entryNtl);

        
    }
}

// TODO:
// - have initial data stored in Core (ntl for spotBalance, etc (can be done by querying the respective precompiles for initial balance/price if its the first time retrieving that data))
// - make it so that every time we access a user's spot/perp balance, we update the ntl using the current info 
// - experiment with archive node and calling precompiles from older, specific block.number (instead of latest by default)
// - enable trading spot/perps
