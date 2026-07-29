// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {CoreWriterLib} from "../../../src/CoreWriterLib.sol";
import {HyperCore} from "../../simulation/HyperCore.sol";
import {CoreSimulatorLib} from "../../simulation/CoreSimulatorLib.sol";

contract OutcomeManager {
    function splitOutcome(uint32 outcome, uint64 amountWei) public {
        CoreWriterLib.splitOutcome(outcome, amountWei);
    }

    function mergeOutcome(uint32 outcome, uint64 amountWei) public {
        CoreWriterLib.mergeOutcome(outcome, amountWei);
    }

    function mergeQuestion(uint32 question, uint64 amountWei) public {
        CoreWriterLib.mergeQuestion(question, amountWei);
    }

    function negateOutcome(uint32 question, uint32 outcome, uint64 amountWei) public {
        CoreWriterLib.negateOutcome(question, outcome, amountWei);
    }
}

contract OutcomeTest is Test {
    event RawAction(address indexed user, bytes data);

    address constant CORE_WRITER_ADDRESS = 0x3333333333333333333333333333333333333333;

    HyperCore public hyperCore;
    address public user = makeAddr("user");

    OutcomeManager public manager;

    function setUp() public {
        hyperCore = CoreSimulatorLib.init();
        hyperCore.setUseRealL1Read(false);
        CoreSimulatorLib.setRevertOnFailure(true);

        manager = new OutcomeManager();
        CoreSimulatorLib.forceAccountActivation(user);
        CoreSimulatorLib.forceAccountActivation(address(manager));
    }

    /*//////////////////////////////////////////////////////////////
                        OUTCOME OPERATION TESTS
    //////////////////////////////////////////////////////////////*/

    // Expected payloads are built from spec literals (version 1, action 17, tuple
    // (encodedOperation, question, outcome, wei)) rather than the library's own
    // constants, so a mis-encoding in CoreWriterLib fails these assertions.
    function testOutcomeOperations() public {
        vm.startPrank(user);

        // SplitOutcome (op 0): question unused, must be 0
        vm.expectEmit(CORE_WRITER_ADDRESS);
        emit RawAction(
            address(manager),
            abi.encodePacked(uint8(1), uint24(17), abi.encode(uint8(0), uint32(0), uint32(1), uint64(100e8)))
        );
        manager.splitOutcome(1, 100e8);

        // MergeOutcome (op 1): question unused, must be 0
        vm.expectEmit(CORE_WRITER_ADDRESS);
        emit RawAction(
            address(manager),
            abi.encodePacked(uint8(1), uint24(17), abi.encode(uint8(1), uint32(0), uint32(1), uint64(50e8)))
        );
        manager.mergeOutcome(1, 50e8);

        // MergeQuestion (op 2): outcome unused, must be 0; wei 0 = merge maximal amount
        vm.expectEmit(CORE_WRITER_ADDRESS);
        emit RawAction(
            address(manager),
            abi.encodePacked(uint8(1), uint24(17), abi.encode(uint8(2), uint32(2), uint32(0), uint64(0)))
        );
        manager.mergeQuestion(2, 0);

        // NegateOutcome (op 3): uses both question and outcome
        vm.expectEmit(CORE_WRITER_ADDRESS);
        emit RawAction(
            address(manager),
            abi.encodePacked(uint8(1), uint24(17), abi.encode(uint8(3), uint32(2), uint32(1), uint64(10e8)))
        );
        manager.negateOutcome(2, 1, 10e8);

        vm.stopPrank();

        // All outcome operations should succeed without revert
        CoreSimulatorLib.nextBlock();
    }

    /*//////////////////////////////////////////////////////////////
                        OUTCOME STATUS TESTS
    //////////////////////////////////////////////////////////////*/

    function testOutcomeStatusDefault() public {
        PrecompileLib.OutcomeStatus memory status = PrecompileLib.outcomeStatus(123);
        assertEq(status.status, 0);
        assertEq(status.settledValue, 0);
        assertEq(status.question, type(uint32).max);
    }

    function testForceOutcomeStatusActive() public {
        CoreSimulatorLib.forceOutcomeStatus(7, 1, 0, 3);

        PrecompileLib.OutcomeStatus memory status = PrecompileLib.outcomeStatus(7);
        assertEq(status.status, 1);
        assertEq(status.settledValue, 0);
        assertEq(status.question, 3);
    }

    function testForceOutcomeStatusSettled() public {
        // settled at 0.75 (settledValue is scaled so that 100_000_000 represents 1.0)
        CoreSimulatorLib.forceOutcomeStatus(8, 2, 75_000_000, 3);

        PrecompileLib.OutcomeStatus memory status = PrecompileLib.outcomeStatus(8);
        assertEq(status.status, 2);
        assertEq(status.settledValue, 75_000_000);
        assertEq(status.question, 3);
    }

    function testForceOutcomeStatusStandalone() public {
        CoreSimulatorLib.forceOutcomeStatus(9, 1, 0, type(uint32).max);

        PrecompileLib.OutcomeStatus memory status = PrecompileLib.outcomeStatus(9);
        assertEq(status.status, 1);
        assertEq(status.question, type(uint32).max);
    }
}
