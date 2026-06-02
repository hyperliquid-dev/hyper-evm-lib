// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {CoreExecution} from "./hyper-core/CoreExecution.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {HLConstants} from "../../src/PrecompileLib.sol";

contract HyperCore is CoreExecution {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    function executeRawAction(address sender, bytes4 action, bytes calldata data) public payable {
        if (action == HLConstants.LIMIT_ORDER_ACTION) {
            LimitOrderAction memory order = abi.decode(data, (LimitOrderAction));

            // for perps (check that the ID is not a spot asset ID)
            if (order.asset < 1e4 || order.asset >= 1e5) {
                executePerpLimitOrder(sender, order);
            } else {
                executeSpotLimitOrder(sender, order);
            }
            return;
        }

        if (action == HLConstants.VAULT_TRANSFER_ACTION) {
            executeVaultTransfer(sender, abi.decode(data, (VaultTransferAction)));
            return;
        }

        if (action == HLConstants.TOKEN_DELEGATE_ACTION) {
            executeTokenDelegate(sender, abi.decode(data, (TokenDelegateAction)));
            return;
        }

        if (action == HLConstants.STAKING_DEPOSIT_ACTION) {
            executeStakingDeposit(sender, abi.decode(data, (StakingDepositAction)));
            return;
        }

        if (action == HLConstants.STAKING_WITHDRAW_ACTION) {
            executeStakingWithdraw(sender, abi.decode(data, (StakingWithdrawAction)));
            return;
        }

        if (action == HLConstants.SPOT_SEND_ACTION) {
            executeSpotSend(sender, abi.decode(data, (SpotSendAction)));
            return;
        }

        if (action == HLConstants.SEND_ASSET_ACTION) {
            executeSendAsset(sender, abi.decode(data, (SendAssetAction)));
            return;
        }

        if (action == HLConstants.USD_CLASS_TRANSFER_ACTION) {
            executeUsdClassTransfer(sender, abi.decode(data, (UsdClassTransferAction)));
            return;
        }
    }

    /// @dev unstaking takes 7 days and after which it will automatically appear in the users
    /// spot balance so we need to check this at the end of each operation to simulate that.
    function processStakingWithdrawals() public {
        while (_withdrawQueue.length() > 0) {
            WithdrawRequest memory request = deserializeWithdrawRequest(_withdrawQueue.front());

            if (request.lockedUntilTimestamp > block.timestamp) {
                break;
            }

            _withdrawQueue.popFront();

            _accounts[request.account].spot[HLConstants.hypeTokenIndex()] += request.amount;
        }
    }
}
