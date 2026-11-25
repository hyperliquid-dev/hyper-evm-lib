// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test} from "forge-std/Test.sol";
import {CoreWriterLib, HLConstants} from "../../src/CoreWriterLib.sol";

/// @dev Records the raw action bytes sent to CoreWriter
contract RecordingCoreWriter {
    bytes public lastAction;

    function sendRawAction(bytes calldata data) external {
        lastAction = data;
    }
}

contract OutcomeCaller {
    function outcomeOperation(uint8 encodedOperation, uint32 question, uint32 outcome, uint64 amountWei) external {
        CoreWriterLib.outcomeOperation(encodedOperation, question, outcome, amountWei);
    }
}

contract CoreWriterEncodingTest is Test {
    RecordingCoreWriter constant CORE_WRITER = RecordingCoreWriter(0x3333333333333333333333333333333333333333);

    OutcomeCaller caller;

    function setUp() public {
        vm.etch(address(CORE_WRITER), address(new RecordingCoreWriter()).code);
        caller = new OutcomeCaller();
    }

    function test_outcomeOperation_encoding() public {
        caller.outcomeOperation(HLConstants.OUTCOME_NEGATE_OUTCOME, 5, 12, 1e8);

        bytes memory expected = abi.encodePacked(
            hex"01000011", // version 1, action ID 17
            abi.encode(uint8(3), uint32(5), uint32(12), uint64(1e8))
        );
        assertEq(CORE_WRITER.lastAction(), expected);
        assertEq(CORE_WRITER.lastAction().length, 4 + 4 * 32);
    }

    function test_outcomeOperation_constants() public pure {
        assertEq(HLConstants.OUTCOME_OPERATION_ACTION, 17);
        assertEq(HLConstants.OUTCOME_SPLIT_OUTCOME, 0);
        assertEq(HLConstants.OUTCOME_MERGE_OUTCOME, 1);
        assertEq(HLConstants.OUTCOME_MERGE_QUESTION, 2);
        assertEq(HLConstants.OUTCOME_NEGATE_OUTCOME, 3);
    }
}
