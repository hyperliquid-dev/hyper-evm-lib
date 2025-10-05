// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PrecompileLib} from "../../src/PrecompileLib.sol";
import {CoreSimulatorLib} from "../simulation/CoreSimulatorLib.sol";

contract StakingBalanceTest is Test {
    function setUp() public {
        vm.createSelectFork("https://rpc.hyperliquid.xyz/evm");
        CoreSimulatorLib.init();
    }

    function test_liveStakingBalance() public {
        address stakingAddress = 0x77C3Ea550D2Da44B120e55071f57a108f8dd5E45;

        PrecompileLib.DelegatorSummary memory summary = PrecompileLib.delegatorSummary(stakingAddress);
        uint256 totalStaking = uint256(summary.delegated);

        emit log_named_uint("total staking balance (core units)", totalStaking);

        assertGt(totalStaking, 0);
    }
}
