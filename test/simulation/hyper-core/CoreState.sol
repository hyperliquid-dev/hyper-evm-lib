// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Heap} from "@openzeppelin/contracts/utils/structs/Heap.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PrecompileLib} from "src/PrecompileLib.sol";
import {HLConstants} from "src/CoreWriterLib.sol";
import {console} from "forge-std/console.sol";

import {RealL1Read} from "../../utils/RealL1Read.sol";
import {StdCheats, Vm} from "forge-std/StdCheats.sol";

uint64 constant KNOWN_TOKEN_USDC = 0;
uint64 constant KNOWN_TOKEN_HYPE = 150;

/// Modified from https://github.com/ambitlabsxyz/hypercore
contract CoreState is StdCheats {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using Heap for Heap.Uint256Heap;

    using RealL1Read for *;

    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    struct WithdrawRequest {
        address account;
        uint64 amount;
        uint32 lockedUntilTimestamp;
    }

    struct AccountData {
        bool created;
        uint64 perpBalance;
        mapping(uint64 token => uint64 balance) spot;
        mapping(address vault => PrecompileLib.UserVaultEquity) vaultEquity;
        uint64 staking;
        mapping(address validator => PrecompileLib.Delegation) delegations;
        mapping(uint16 perpIndex => PrecompileLib.Position) positions;
    }

    struct PendingOrder {
        address sender;
        LimitOrderAction action;
    }

    // registered token info
    mapping(uint64 token => PrecompileLib.TokenInfo) internal _tokens;

    mapping(address account => AccountData) internal _accounts;

    mapping(address account => bool initialized) internal _initializedAccounts;
    mapping(address account => mapping(uint64 token => bool initialized)) internal _initializedSpotBalance;
    mapping(address account => mapping(address vault => bool initialized)) internal _initializedVaults;
    mapping(address account => mapping(uint32 perpIndex => bool initialized)) internal _initializedPerpPosition;

    mapping(address account => mapping(uint64 token => uint64 latentBalance)) internal _latentSpotBalance;

    mapping(uint32 perpIndex => uint64 markPrice) internal _perpMarkPrice;
    mapping(uint32 spotMarketId => uint64 spotPrice) internal _spotPrice;

    mapping(address vault => uint64) internal _vaultEquity;

    DoubleEndedQueue.Bytes32Deque internal _withdrawQueue;

    PendingOrder[] internal _pendingOrders;

    EnumerableSet.AddressSet internal _validators;

    /////////////////////////
    /// STATE INITIALIZERS///
    /////////////////////////

    modifier initAccountWithToken(address _account, uint64 token) {
        if (!_initializedSpotBalance[_account][token]) {
            registerTokenInfo(token);
            _initializeAccountWithToken(_account, token);
        }
        _;
    }

    modifier initAccountWithSpotMarket(address _account, uint32 spotMarketId) {
        uint64 baseToken = PrecompileLib.spotInfo(spotMarketId).tokens[0];
        uint64 quoteToken = PrecompileLib.spotInfo(spotMarketId).tokens[1];

        if (!_initializedSpotBalance[_account][baseToken]) {
            registerTokenInfo(baseToken);
            _initializeAccountWithToken(_account, baseToken);
        }

        if (!_initializedSpotBalance[_account][quoteToken]) {
            registerTokenInfo(quoteToken);
            _initializeAccountWithToken(_account, quoteToken);
        }

        _;
    }

    modifier initAccountWithVault(address _account, address _vault) {
        if (!_initializedVaults[_account][_vault]) {
            _initializeAccount(_account);
            _initializeAccountWithVault(_account, _vault);
        }
        _;
    }

    modifier initAccountWithPerp(address _account, uint16 perp) {
        if (_initializedPerpPosition[_account][perp] == false) {
            _initializeAccount(_account);
            _initializeAccountWithPerp(_account, perp);
        }
        _;
    }

    modifier initAccount(address _account) {
        if (!_initializedAccounts[_account]) {
            _initializeAccount(_account);
        }
        _;
    }

    function _initializeAccountWithToken(address _account, uint64 token) internal {
        _initializeAccount(_account);

        if (_accounts[_account].created == false) {
            return;
        }

        _initializedSpotBalance[_account][token] = true;
        _accounts[_account].spot[token] = RealL1Read.spotBalance(_account, token).total;
    }

    function _initializeAccountWithVault(address _account, address _vault) internal {
        _initializedVaults[_account][_vault] = true;
        _accounts[_account].vaultEquity[_vault] = RealL1Read.userVaultEquity(_account, _vault);
    }

    function _initializeAccountWithPerp(address _account, uint16 perp) internal {
        _initializedPerpPosition[_account][perp] = true;
        _accounts[_account].positions[perp] = RealL1Read.position(_account, perp);
    }

    function _initializeAccount(address _account) internal {
        bool initialized = _initializedAccounts[_account];

        if (initialized) {
            return;
        }

        AccountData storage account = _accounts[_account];

        // check if the acc is created on Core
        RealL1Read.CoreUserExists memory coreUserExists = RealL1Read.coreUserExists(_account);
        if (!coreUserExists.exists) {
            return;
        }

        _initializedAccounts[_account] = true;
        account.created = true;

        // setting perp balance
        account.perpBalance = RealL1Read.withdrawable(_account).withdrawable;

        // setting staking balance
        PrecompileLib.DelegatorSummary memory summary = RealL1Read.delegatorSummary(_account);
        account.staking = summary.undelegated;
        // note: no way to track the pending withdrawals, and have a way to credit them later

        // set delegations
        PrecompileLib.Delegation[] memory delegations = RealL1Read.delegations(_account);
        for (uint256 i = 0; i < delegations.length; i++) {
            account.delegations[delegations[i].validator] = delegations[i];
        }
    }

    modifier whenAccountCreated(address sender) {
        if (_accounts[sender].created == false) {
            return;
        }
        _;
    }

    function registerTokenInfo(uint64 index) public {
        // if the token is already registered, return early
        if (bytes(_tokens[index].name).length > 0) {
            return;
        }

        PrecompileLib.TokenInfo memory tokenInfo = RealL1Read.tokenInfo(uint32(index));

        // this means that the precompile call failed
        if (tokenInfo.evmContract == RealL1Read.INVALID_ADDRESS) return;
        _tokens[index] = tokenInfo;
    }

    function registerValidator(address validator) public {
        _validators.add(validator);
    }

    /// @dev account creation can be forced when there isnt a reliance on testing that workflow.
    function forceAccountCreation(address account) public {
        _accounts[account].created = true;
    }

    function forceSpot(address account, uint64 token, uint64 _wei)
        public
        payable
        initAccountWithToken(account, token)
    {
        _accounts[account].spot[token] = _wei;
    }

    function forcePerpBalance(address account, uint64 usd) public payable {
        forceAccountCreation(account);
        _accounts[account].perpBalance = usd;
    }

    function forceStaking(address account, uint64 _wei) public payable {
        forceAccountCreation(account);
        _accounts[account].staking = _wei;
    }

    function forceDelegation(address account, address validator, uint64 amount, uint64 lockedUntilTimestamp) public {
        forceAccountCreation(account);
        _accounts[account].delegations[validator] =
            PrecompileLib.Delegation({validator: validator, amount: amount, lockedUntilTimestamp: lockedUntilTimestamp});
    }

    function forceVaultEquity(address account, address vault, uint64 usd, uint64 lockedUntilTimestamp) public payable {
        forceAccountCreation(account);

        _vaultEquity[vault] -= _accounts[account].vaultEquity[vault].equity;
        _vaultEquity[vault] += usd;

        _accounts[account].vaultEquity[vault].equity = usd;
        _accounts[account].vaultEquity[vault].lockedUntilTimestamp =
            lockedUntilTimestamp > 0 ? lockedUntilTimestamp : uint64((block.timestamp + 3600) * 1000);
    }

    //////// conversions ////////

    function toWei(uint256 amount, int8 evmExtraWeiDecimals) internal pure returns (uint64) {
        uint256 _wei = evmExtraWeiDecimals == 0
            ? amount
            : evmExtraWeiDecimals > 0
                ? amount / 10 ** uint8(evmExtraWeiDecimals)
                : amount * 10 ** uint8(-evmExtraWeiDecimals);

        return _wei.toUint64();
    }

    function fromWei(uint64 _wei, int8 evmExtraWeiDecimals) internal pure returns (uint256) {
        return evmExtraWeiDecimals == 0
            ? _wei
            : evmExtraWeiDecimals > 0 ? _wei * 10 ** uint8(evmExtraWeiDecimals) : _wei / 10 ** uint8(-evmExtraWeiDecimals);
    }

    function fromPerp(uint64 usd) internal pure returns (uint64) {
        return usd * 1e2;
    }

    // converting a withdraw request into a bytes32
    function serializeWithdrawRequest(CoreState.WithdrawRequest memory request) internal pure returns (bytes32) {
        return bytes32(
            (uint256(uint160(request.account)) << 96) | (uint256(request.amount) << 32)
                | uint40(request.lockedUntilTimestamp)
        );
    }

    function deserializeWithdrawRequest(bytes32 data)
        internal
        pure
        returns (CoreState.WithdrawRequest memory request)
    {
        request.account = address(uint160(uint256(data) >> 96));
        request.amount = uint64(uint256(data) >> 32);
        request.lockedUntilTimestamp = uint32(uint256(data));
    }

    struct LimitOrderAction {
        uint32 asset;
        bool isBuy;
        uint64 limitPx;
        uint64 sz;
        bool reduceOnly;
        uint8 encodedTif;
        uint128 cloid;
    }

    struct VaultTransferAction {
        address vault;
        bool isDeposit;
        uint64 usd;
    }

    struct TokenDelegateAction {
        address validator;
        uint64 _wei;
        bool isUndelegate;
    }

    struct StakingDepositAction {
        uint64 _wei;
    }

    struct StakingWithdrawAction {
        uint64 _wei;
    }

    struct SpotSendAction {
        address destination;
        uint64 token;
        uint64 _wei;
    }

    struct UsdClassTransferAction {
        uint64 ntl;
        bool toPerp;
    }
}
