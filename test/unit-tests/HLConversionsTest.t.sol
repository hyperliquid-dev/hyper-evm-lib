// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {CoreSimulatorLib} from "../simulation/CoreSimulatorLib.sol";
import {HLConversions} from "../../src/common/HLConversions.sol";

contract HLConversionsTest is Test {
    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        CoreSimulatorLib.init();
    }

    // HOPE (token 122) has evmExtraWeiDecimals == 0
    uint64 constant HOPE_TOKEN = 122;
    // PURR (token 1) has evmExtraWeiDecimals == 13 (positive)
    uint64 constant PURR_TOKEN = 1;
    // USDC (token 0) has evmExtraWeiDecimals == -2 (negative)
    uint64 constant USDC_TOKEN = 0;

    function test_evmToWei_zeroExtraDecimals() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(uint32(HOPE_TOKEN));
        assertEq(info.evmExtraWeiDecimals, 0);
        assertTrue(info.evmContract != address(0));

        uint64 result = HLConversions.evmToWei(HOPE_TOKEN, 1000);
        assertEq(result, 1000);
    }

    function test_weiToEvm_zeroExtraDecimals() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(uint32(HOPE_TOKEN));
        assertEq(info.evmExtraWeiDecimals, 0);
        assertTrue(info.evmContract != address(0));

        uint256 result = HLConversions.weiToEvm(HOPE_TOKEN, 1000);
        assertEq(result, 1000);
    }

    function test_roundtrip_zeroExtraDecimals() public view {
        uint64 wei_ = HLConversions.evmToWei(HOPE_TOKEN, 5000);
        uint256 backToEvm = HLConversions.weiToEvm(HOPE_TOKEN, wei_);
        assertEq(backToEvm, 5000);
    }

    function test_evmToWei_positiveExtraDecimals() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(uint32(PURR_TOKEN));
        assertTrue(info.evmExtraWeiDecimals > 0);

        // 1e18 evm amount / 10^13 = 1e5 wei
        uint256 evmAmount = 1e18;
        uint64 result = HLConversions.evmToWei(PURR_TOKEN, evmAmount);
        uint64 expected = uint64(evmAmount / (10 ** uint8(info.evmExtraWeiDecimals)));
        assertEq(result, expected);
    }

    function test_weiToEvm_positiveExtraDecimals() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(uint32(PURR_TOKEN));
        assertTrue(info.evmExtraWeiDecimals > 0);

        uint64 weiAmount = 1000;
        uint256 result = HLConversions.weiToEvm(PURR_TOKEN, weiAmount);
        uint256 expected = uint256(weiAmount) * (10 ** uint8(info.evmExtraWeiDecimals));
        assertEq(result, expected);
    }

    function test_evmToWei_negativeExtraDecimals() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(uint32(USDC_TOKEN));
        assertTrue(info.evmExtraWeiDecimals < 0);

        // 1000 USDC in evm (6 decimals) -> wei should multiply by 10^2
        uint256 evmAmount = 1000e6;
        uint64 result = HLConversions.evmToWei(USDC_TOKEN, evmAmount);
        uint64 expected = uint64(evmAmount * (10 ** uint8(-info.evmExtraWeiDecimals)));
        assertEq(result, expected);
    }

    function test_weiToEvm_negativeExtraDecimals() public view {
        PrecompileLib.TokenInfo memory info = PrecompileLib.tokenInfo(uint32(USDC_TOKEN));
        assertTrue(info.evmExtraWeiDecimals < 0);

        uint64 weiAmount = 1000e8;
        uint256 result = HLConversions.weiToEvm(USDC_TOKEN, weiAmount);
        uint256 expected = uint256(weiAmount) / (10 ** uint8(-info.evmExtraWeiDecimals));
        assertEq(result, expected);
    }
}
