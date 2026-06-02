// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICoreWriter} from "../interfaces/ICoreWriter.sol";

library HLConstants {
    /*//////////////////////////////////////////////////////////////
                        Precompiles
    //////////////////////////////////////////////////////////////*/

    address constant POSITION_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000800;
    address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;
    address constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;
    address constant WITHDRAWABLE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000803;
    address constant DELEGATIONS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000804;
    address constant DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000805;
    address constant MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;
    address constant ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;
    address constant SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;
    address constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;
    address constant PERP_ASSET_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080a;
    address constant SPOT_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080b;
    address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;
    address constant TOKEN_SUPPLY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080D;
    address constant BBO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080e;
    address constant ACCOUNT_MARGIN_SUMMARY_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080F;
    address constant CORE_USER_EXISTS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000810;
    address constant BORROW_LEND_USER_STATE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000811;
    address constant BORROW_LEND_RESERVE_STATE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000812;
    address constant POSITION2_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000813;

    /*//////////////////////////////////////////////////////////////
                        Other addresses and constants
    //////////////////////////////////////////////////////////////*/

    uint160 constant BASE_SYSTEM_ADDRESS = uint160(0x2000000000000000000000000000000000000000);
    address constant HYPE_SYSTEM_ADDRESS = 0x2222222222222222222222222222222222222222;

    address constant USDC_EVM_CONTRACT = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;
    address constant TESTNET_USDC_CONTRACT = 0x2B3370eE501B4a559b57D449569354196457D8Ab;

    address constant CORE_DEPOSIT_WALLET = 0x6B9E773128f453f5c2C60935Ee2DE2CBc5390A24;
    address constant TESTNET_CORE_DEPOSIT_WALLET = 0x0B80659a4076E9E93C7DbE0f10675A16a3e5C206;

    uint64 constant USDC_TOKEN_INDEX = 0;
    uint8 constant HYPE_EVM_EXTRA_DECIMALS = 10;

    /*//////////////////////////////////////////////////////////////
                        HYPE Utils
    //////////////////////////////////////////////////////////////*/
    function hypeTokenIndex() internal view returns (uint64) {
        return block.chainid == 998 ? 1105 : 150;
    }

    function isHype(uint64 index) internal view returns (bool) {
        return index == hypeTokenIndex();
    }

    /*//////////////////////////////////////////////////////////////
                        USDC Utils
    //////////////////////////////////////////////////////////////*/
    function isUsdc(uint64 index) internal pure returns (bool) {
        return index == USDC_TOKEN_INDEX;
    }

    function usdc() internal view returns (address) {
        return block.chainid == 998 ? TESTNET_USDC_CONTRACT : USDC_EVM_CONTRACT;
    }

    function coreDepositWallet() internal view returns (address) {
        return block.chainid == 998 ? TESTNET_CORE_DEPOSIT_WALLET : CORE_DEPOSIT_WALLET;
    }

    /*//////////////////////////////////////////////////////////////
                        CoreWriter Actions
    //////////////////////////////////////////////////////////////*/

    // 4-byte action selectors: version byte 0x01 ++ 3-byte action ID. Passing one of these to
    // `abi.encodeWithSelector(action, args...)` produces the exact CoreWriter wire format
    // (version byte ++ action ID ++ abi-encoded args) in a single allocation. The simulator
    // also matches against these to dispatch raw action bytes.
    bytes4 constant LIMIT_ORDER_ACTION = 0x01000001;
    bytes4 constant VAULT_TRANSFER_ACTION = 0x01000002;
    bytes4 constant TOKEN_DELEGATE_ACTION = 0x01000003;
    bytes4 constant STAKING_DEPOSIT_ACTION = 0x01000004;
    bytes4 constant STAKING_WITHDRAW_ACTION = 0x01000005;
    bytes4 constant SPOT_SEND_ACTION = 0x01000006;
    bytes4 constant USD_CLASS_TRANSFER_ACTION = 0x01000007;
    bytes4 constant FINALIZE_EVM_CONTRACT_ACTION = 0x01000008;
    bytes4 constant ADD_API_WALLET_ACTION = 0x01000009;
    bytes4 constant CANCEL_ORDER_BY_OID_ACTION = 0x0100000a;
    bytes4 constant CANCEL_ORDER_BY_CLOID_ACTION = 0x0100000b;
    bytes4 constant APPROVE_BUILDER_FEE_ACTION = 0x0100000c;
    bytes4 constant SEND_ASSET_ACTION = 0x0100000d;
    bytes4 constant REFLECT_EVM_SUPPLY_CHANGE_ACTION = 0x0100000e;
    bytes4 constant BORROW_LEND_OPERATION_ACTION = 0x0100000f;

    /*//////////////////////////////////////////////////////////////
                        Precompile Gas Caps
    //////////////////////////////////////////////////////////////*/

    // Cost formula: 2000 + 65 * (input_len + output_len). Caps are ~20% above
    // formula, rounded up. Prevents invalid inputs from consuming all remaining
    // gas in the call frame. Functions with dynamic-length outputs are uncapped.
    uint256 constant POSITION_GAS = 20_000; // 2000 + 65*(64+160) = 16560
    uint256 constant SPOT_BALANCE_GAS = 15_000; // 2000 + 65*(64+96)  = 12400
    uint256 constant VAULT_EQUITY_GAS = 12_500; // 2000 + 65*(64+64)  = 10320
    uint256 constant WITHDRAWABLE_GAS = 7500; // 2000 + 65*(32+32)  = 6160
    uint256 constant DELEGATOR_SUMMARY_GAS = 15_000; // 2000 + 65*(32+128) = 12400
    uint256 constant MARK_PX_GAS = 7500; // 2000 + 65*(32+32)  = 6160
    uint256 constant ORACLE_PX_GAS = 7500; // 2000 + 65*(32+32)  = 6160
    uint256 constant SPOT_PX_GAS = 7500; // 2000 + 65*(32+32)  = 6160
    uint256 constant L1_BLOCK_NUMBER_GAS = 5000; // 2000 + 65*(0+32)   = 4080
    uint256 constant BBO_GAS = 10_000; // 2000 + 65*(32+64)  = 8240
    uint256 constant ACCOUNT_MARGIN_SUMMARY_GAS = 17_500; // 2000 + 65*(64+128) = 14480
    uint256 constant CORE_USER_EXISTS_GAS = 7500; // 2000 + 65*(32+32)  = 6160
    uint256 constant BORROW_LEND_USER_STATE_GAS = 17_500; // 2000 + 65*(64+128) = 14480
    uint256 constant BORROW_LEND_RESERVE_STATE_GAS = 25_000; // 2000 + 65*(32+256) = 20720

    /*//////////////////////////////////////////////////////////////
                        Limit Order Time in Force
    //////////////////////////////////////////////////////////////*/

    uint8 public constant LIMIT_ORDER_TIF_ALO = 1;
    uint8 public constant LIMIT_ORDER_TIF_GTC = 2;
    uint8 public constant LIMIT_ORDER_TIF_IOC = 3;

    /*//////////////////////////////////////////////////////////////
                        Miscellaneous
    //////////////////////////////////////////////////////////////*/

    // `encodedOperation` for `borrowLend` CoreWriter action
    uint8 public constant BLP_SUPPLY = 0;
    uint8 public constant BLP_WITHDRAW = 1;

    /*//////////////////////////////////////////////////////////////
                        Dex Constants
    //////////////////////////////////////////////////////////////*/
    uint32 constant DEFAULT_PERP_DEX = 0;
    uint32 constant SPOT_DEX = type(uint32).max;
}

