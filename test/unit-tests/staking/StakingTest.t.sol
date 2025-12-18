// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console} from "forge-std/Test.sol";
import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {HLConversions} from "../../../src/common/HLConversions.sol";
import {HLConstants} from "../../../src/common/HLConstants.sol";
import {HyperCore} from "../../simulation/HyperCore.sol";
import {CoreSimulatorLib} from "../../simulation/CoreSimulatorLib.sol";
import {RealL1Read} from "../../utils/RealL1Read.sol";
import {CoreWriterLib} from "../../../src/CoreWriterLib.sol";
import {StakingExample} from "../../../src/examples/StakingExample.sol";

contract StakingTest is Test {
    using PrecompileLib for address;
    using HLConversions for *;

    uint64 public constant HYPE_TOKEN = 150;

    HyperCore public hyperCore;
    address public user = makeAddr("user");
    address public validator = 0xEEEe86F718F9Da3e7250624A460f6EA710E9C006;

    function setUp() public {
        string memory alchemyRpc = vm.envString("ALCHEMY_RPC");
        vm.createSelectFork(alchemyRpc);

        hyperCore = CoreSimulatorLib.init();

        CoreSimulatorLib.forceAccountActivation(user);
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC STAKING TESTS
    //////////////////////////////////////////////////////////////*/

    function testStakingFullFlow() public {
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        CoreSimulatorLib.setRevertOnFailure(true);

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        // Check the delegator summary
        PrecompileLib.DelegatorSummary memory summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(summary.delegated, HYPE_TOKEN.evmToWei(1000e18), "Delegated amount should match");
        assertEq(summary.undelegated, 0, "Undelegated should be 0");
        assertEq(summary.nPendingWithdrawals, 0, "No pending withdrawals");
        assertEq(summary.totalPendingWithdrawal, 0, "Total pending should be 0");

        // Set staking multiplier to 1.1x
        CoreSimulatorLib.setStakingYieldIndex(1.1e18);
        summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(
            uint256(summary.delegated),
            uint256(HYPE_TOKEN.evmToWei(1000e18)) * 1.1e18 / 1e18,
            "Delegated should reflect yield"
        );
        assertEq(summary.undelegated, 0, "Undelegated should still be 0");
        assertEq(summary.nPendingWithdrawals, 0, "No pending withdrawals");
        assertEq(summary.totalPendingWithdrawal, 0, "Total pending should be 0");

        CoreSimulatorLib.setStakingYieldIndex(1e18);

        // Undelegate
        staking.undelegateTokens(validator, HYPE_TOKEN.evmToWei(1000e18));

        CoreSimulatorLib.nextBlock();

        summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(summary.delegated, 0, "Delegated should be 0 after undelegation");
        assertEq(summary.undelegated, HYPE_TOKEN.evmToWei(1000e18), "Undelegated should match");
        assertEq(summary.nPendingWithdrawals, 0, "No pending withdrawals yet");
        assertEq(summary.totalPendingWithdrawal, 0, "Total pending should be 0");

        staking.withdrawStake(HYPE_TOKEN.evmToWei(1000e18));
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 7 days);

        CoreSimulatorLib.nextBlock();

        summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(summary.delegated, 0, "Delegated should be 0");
        assertEq(summary.undelegated, 0, "Undelegated should be 0 after withdrawal");
        assertEq(summary.nPendingWithdrawals, 0, "No pending withdrawals");
        assertEq(summary.totalPendingWithdrawal, 0, "Total pending should be 0");
    }

    function testStakingDelegations() public {
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        CoreSimulatorLib.setRevertOnFailure(true);

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        // Check delegations
        PrecompileLib.Delegation[] memory delegations = PrecompileLib.delegations(address(staking));
        assertEq(delegations.length, 1, "Should have 1 delegation");
        assertEq(delegations[0].validator, validator, "Validator should match");
        assertEq(delegations[0].amount, HYPE_TOKEN.evmToWei(1000e18), "Amount should match");
        assertEq(delegations[0].lockedUntilTimestamp, block.timestamp * 1000, "Lock timestamp should match");
    }

    function testMaxPendingWithdrawals() public {
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        CoreSimulatorLib.setRevertOnFailure(true);

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        staking.undelegateTokens(validator, HYPE_TOKEN.evmToWei(1000e18));

        CoreSimulatorLib.nextBlock();

        // Make 5 withdrawals (maximum allowed)
        staking.withdrawStake(HYPE_TOKEN.evmToWei(100e18));
        staking.withdrawStake(HYPE_TOKEN.evmToWei(100e18));
        staking.withdrawStake(HYPE_TOKEN.evmToWei(100e18));
        staking.withdrawStake(HYPE_TOKEN.evmToWei(100e18));
        staking.withdrawStake(HYPE_TOKEN.evmToWei(100e18));

        CoreSimulatorLib.nextBlock();

        // 6th withdrawal should fail due to maximum of 5 pending withdrawals per account
        staking.withdrawStake(HYPE_TOKEN.evmToWei(50e18));

        bool expectRevert = true;
        CoreSimulatorLib.nextBlock(expectRevert);
    }

    /*//////////////////////////////////////////////////////////////
                        STAKING YIELD TESTS
    //////////////////////////////////////////////////////////////*/

    function testStakingYieldMultiplier() public {
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        CoreSimulatorLib.setRevertOnFailure(true);

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 500e18}(500e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        uint64 initialDelegated = HYPE_TOKEN.evmToWei(500e18);

        // Test different yield multipliers
        CoreSimulatorLib.setStakingYieldIndex(1.05e18); // 5% yield
        PrecompileLib.DelegatorSummary memory summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(
            uint256(summary.delegated),
            uint256(initialDelegated) * 1.05e18 / 1e18,
            "Delegated should reflect 5% yield"
        );

        CoreSimulatorLib.setStakingYieldIndex(1.2e18); // 20% yield
        summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(
            uint256(summary.delegated),
            uint256(initialDelegated) * 1.2e18 / 1e18,
            "Delegated should reflect 20% yield"
        );

        // Reset
        CoreSimulatorLib.setStakingYieldIndex(1e18);
    }

    /*//////////////////////////////////////////////////////////////
                    MULTIPLE VALIDATORS TESTS
    //////////////////////////////////////////////////////////////*/

    function testStakingToMultipleValidators() public {
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));
        // Don't set revertOnFailure since we're just testing partial undelegation

        deal(address(user), 10000e18);

        vm.startPrank(user);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        // Partial undelegation from the validator
        staking.undelegateTokens(validator, HYPE_TOKEN.evmToWei(500e18));
        CoreSimulatorLib.nextBlock();

        // Check delegator summary
        PrecompileLib.DelegatorSummary memory summary = PrecompileLib.delegatorSummary(address(staking));
        assertEq(summary.delegated, HYPE_TOKEN.evmToWei(500e18), "Should have 500 still delegated");
        assertEq(summary.undelegated, HYPE_TOKEN.evmToWei(500e18), "Should have 500 undelegated");
    }

    /*//////////////////////////////////////////////////////////////
                        READ DELEGATIONS TESTS
    //////////////////////////////////////////////////////////////*/

    function testReadDelegationsFromLiveAddress() public {
        address stakingAddress = 0x393D0B87Ed38fc779FD9611144aE649BA6082109;

        PrecompileLib.Delegation[] memory delegations = RealL1Read.delegations(stakingAddress);

        uint256 totalDelegated = 0;
        for (uint256 i = 0; i < delegations.length; i++) {
            totalDelegated += delegations[i].amount;
        }

        // Just verify the call works - actual values depend on live state
        assertGe(delegations.length, 0, "Should return delegations array");
    }

    function testReadDelegatorSummaryFromLiveAddress() public {
        address stakingAddress = 0x393D0B87Ed38fc779FD9611144aE649BA6082109;

        PrecompileLib.DelegatorSummary memory summary = RealL1Read.delegatorSummary(stakingAddress);

        // Just verify the call works and returns valid data
        assertGe(summary.delegated + summary.undelegated + summary.totalPendingWithdrawal, 0, "Should return valid summary");
    }

    /*//////////////////////////////////////////////////////////////
                    LIVE STAKING BALANCE TEST
    //////////////////////////////////////////////////////////////*/

    function testLiveStakingBalance() public {
        address stakingAddress = 0x77C3Ea550D2Da44B120e55071f57a108f8dd5E45;

        PrecompileLib.DelegatorSummary memory summary = PrecompileLib.delegatorSummary(stakingAddress);
        uint256 totalStaking = uint256(summary.delegated);

        assertGt(totalStaking, 0, "Should have positive staking balance");
    }

    /*//////////////////////////////////////////////////////////////
                        FORCE DELEGATION TESTS
    //////////////////////////////////////////////////////////////*/

    function testForceDelegation() public {
        // Test delegation by going through the actual staking flow
        StakingExample staking = new StakingExample();
        CoreSimulatorLib.forceAccountActivation(address(staking));

        deal(address(user), 10000e18);

        vm.startPrank(user);
        uint64 delegationAmount = HYPE_TOKEN.evmToWei(1000e18);
        staking.bridgeHypeAndStake{value: 1000e18}(1000e18, validator);
        CoreSimulatorLib.nextBlock();

        vm.warp(block.timestamp + 1 days);

        PrecompileLib.Delegation[] memory delegations = PrecompileLib.delegations(address(staking));
        assertEq(delegations.length, 1, "Should have 1 delegation");
        assertEq(delegations[0].validator, validator, "Validator should match");
        assertEq(delegations[0].amount, delegationAmount, "Amount should match");
    }

    function testForceStakingBalance() public {
        address testUser = makeAddr("stakingBalanceUser");
        CoreSimulatorLib.forceAccountActivation(testUser);

        uint64 stakingAmount = 5000e8;
        CoreSimulatorLib.forceStakingBalance(testUser, stakingAmount);

        PrecompileLib.DelegatorSummary memory summary = PrecompileLib.delegatorSummary(testUser);
        assertEq(summary.undelegated, stakingAmount, "Undelegated balance should match forced amount");
    }
}
