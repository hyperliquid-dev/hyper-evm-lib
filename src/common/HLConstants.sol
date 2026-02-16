// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ICoreWriter} from "../interfaces/ICoreWriter.sol";

library HLConstants {
    /*//////////////////////////////////////////////////////////////
                        Addresses
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

    uint24 constant LIMIT_ORDER_ACTION = 1;
    uint24 constant VAULT_TRANSFER_ACTION = 2;

    uint24 constant TOKEN_DELEGATE_ACTION = 3;
    uint24 constant STAKING_DEPOSIT_ACTION = 4;
    uint24 constant STAKING_WITHDRAW_ACTION = 5;

    uint24 constant SPOT_SEND_ACTION = 6;
    uint24 constant USD_CLASS_TRANSFER_ACTION = 7;

    uint24 constant FINALIZE_EVM_CONTRACT_ACTION = 8;
    uint24 constant ADD_API_WALLET_ACTION = 9;
    uint24 constant CANCEL_ORDER_BY_OID_ACTION = 10;
    uint24 constant CANCEL_ORDER_BY_CLOID_ACTION = 11;
    uint24 constant APPROVE_BUILDER_FEE_ACTION = 12;
    uint24 constant SEND_ASSET_ACTION = 13;
    uint24 constant BORROW_LEND_ACTION = 15;

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

