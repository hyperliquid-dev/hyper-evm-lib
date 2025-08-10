// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../src/PrecompileLib.sol";
import {HLConstants} from "../src/common/HLConstants.sol";
import {PrecompileSimulator} from "./utils/PrecompileSimulator.sol";

contract PrecompileLibTests is Test {

    using PrecompileLib for address;

    address public constant USDT0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;
    address public constant uBTC  = 0x9FDBdA0A5e284c32744D2f17Ee5c74B284993463;
    address public constant uETH  = 0xBe6727B535545C67d5cAa73dEa54865B92CF7907;
    address public constant uSOL  = 0x068f321Fa8Fb9f0D135f290Ef6a3e2813e1c8A29;

    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        PrecompileSimulator.init();
    }

    function test_tokenInfo() public {
        PrecompileLib.TokenInfo memory info = USDT0.tokenInfo();
        assertEq(info.name, "USDT0");
    }

    function test_spotInfo() public {
        PrecompileLib.SpotInfo memory info = USDT0.spotInfo();
    }

    function test_spotPx() public {
        uint64 px = USDT0.spotPx();
        console.log("px: %e", px);
    }
    function test_normalizedSpotPrice() public {

        uint64 tokenIndex = USDT0.getTokenIndex();
        uint64 spotIndex = PrecompileLib.getSpotIndex(tokenIndex);

        uint64 spotIndex_alt = PrecompileLib.getSpotIndex(tokenIndex, 0);
        assertEq(spotIndex, spotIndex_alt);
        
        uint256 price = PrecompileLib.normalizedSpotPx(spotIndex);

        console.log("price: %e", price);
        assertApproxEqAbs(price, 1e8, 1e4);
    }

    function test_normalizedMarkPx() public {
        uint256 price = PrecompileLib.normalizedMarkPx(0);
        console.log("BTC price: %e", price);
        assertApproxEqAbs(price, 114000e6, 20000e6);

        price = PrecompileLib.normalizedMarkPx(1);
        console.log("ETH price: %e", price);
        assertApproxEqAbs(price, 4000e6, 2000e6);
    }

    function test_normalizedOraclePrice() public {
        uint256 price = PrecompileLib.normalizedOraclePx(0);
        console.log("BTC price: %e", price);
        assertApproxEqAbs(price, 114000e6, 20000e6);

        price = PrecompileLib.normalizedOraclePx(1);
        console.log("ETH price: %e", price);
        assertApproxEqAbs(price, 4000e6, 2000e6);
    }

    function test_spotBalance() public {
        PrecompileLib.SpotBalance memory balance = PrecompileLib.spotBalance(0xF036a5261406a394bd63Eb4dF49C464634a66155, 150);
        console.log("balance: %e", balance.total);
    }

    function test_bbo() public {

        uint64 tokenIndex = uBTC.getTokenIndex();
        uint64 spotIndex = PrecompileLib.getSpotIndex(tokenIndex);
        uint64 asset = spotIndex + 10000;
        PrecompileLib.Bbo memory bbo = PrecompileLib.bbo(asset);
        console.log("bid: %e", bbo.bid);
        console.log("ask: %e", bbo.ask);
    }

    function test_accountMarginSummary() public {

        address whale = 0x2Ba553d9F990a3B66b03b2dC0D030dfC1c061036;
        PrecompileLib.AccountMarginSummary memory summary = PrecompileLib.accountMarginSummary(0, whale);

        assertGt(summary.marginUsed, 0);
        assertGt(summary.ntlPos, 0);

        console.log("accountValue: %e", summary.accountValue);
        console.log("marginUsed: %e", summary.marginUsed);
        console.log("ntlPos: %e", summary.ntlPos);
        console.log("rawUsd: %e", summary.rawUsd);
    }

    function test_coreUserExists() public {
        address whale = 0x2Ba553d9F990a3B66b03b2dC0D030dfC1c061036;
        address whale2 = 0x751140B83d289353B3B6dA2c7e8659b3a0642F11;

        bool exists = PrecompileLib.coreUserExists(whale);
        bool exists2 = PrecompileLib.coreUserExists(whale2);

        assertEq(exists, true);
        assertEq(exists2, false);
    }

    function test_l1BlockNumber() public {
        uint64 blockNumber = PrecompileLib.l1BlockNumber();
        console.log("L1 block number:", blockNumber);

        console.log("EVM block number:", block.number);

        assertGt(blockNumber, block.number);
    }



}
