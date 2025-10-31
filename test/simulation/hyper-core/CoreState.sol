// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {DoubleEndedQueue} from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import {Heap} from "@openzeppelin/contracts/utils/structs/Heap.sol";

import {PrecompileLib} from "../../../src/PrecompileLib.sol";
import {HLConstants} from "../../../src/CoreWriterLib.sol";

import {RealL1Read} from "../../utils/RealL1Read.sol";
import {StdCheats, Vm} from "forge-std/StdCheats.sol";

/// Modified from https://github.com/ambitlabsxyz/hypercore
contract CoreState is StdCheats {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.AddressSet;
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
    using Heap for Heap.Uint256Heap;

    using RealL1Read for *;

    Vm internal constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint64 public immutable HYPE_TOKEN_INDEX;
    uint64 public constant USDC_TOKEN_INDEX = 0;

    constructor() {
        HYPE_TOKEN_INDEX = HLConstants.hypeTokenIndex();
    }

    struct WithdrawRequest {
        address account;
        uint64 amount;
        uint32 lockedUntilTimestamp;
    }

    struct AccountData {
        bool activated;
        mapping(uint64 token => uint64 balance) spot;
        mapping(address vault => PrecompileLib.UserVaultEquity) vaultEquity;
        uint64 staking;
        EnumerableSet.AddressSet delegatedValidators;
        mapping(address validator => PrecompileLib.Delegation) delegations;
        uint64 perpBalance;
        mapping(uint16 perpIndex => PrecompileLib.Position) positions;
        mapping(uint16 perpIndex => uint64 margin) margin;
        mapping(uint16 perpIndex => PrecompileLib.AccountMarginSummary) marginSummary;
    }

    struct PendingOrder {
        address sender;
        LimitOrderAction action;
    }

    // Whether to use real L1 read or not
    bool public useRealL1Read;

    // registered token info
    mapping(uint64 token => PrecompileLib.TokenInfo) internal _tokens;

    mapping(address account => AccountData) internal _accounts;

    mapping(address account => bool initialized) internal _initializedAccounts;
    mapping(address account => mapping(uint64 token => bool initialized)) internal _initializedSpotBalance;
    mapping(address account => mapping(address vault => bool initialized)) internal _initializedVaults;

    mapping(address account => mapping(uint32 perpIndex => bool initialized)) internal _initializedPerpPosition;
    mapping(uint16 perpIndex => uint32 maxLeverage) internal _maxLeverage;

    mapping(address account => mapping(uint64 token => uint64 latentBalance)) internal _latentSpotBalance;

    mapping(uint32 perpIndex => uint64 markPrice) internal _perpMarkPrice;
    mapping(uint32 spotMarketId => uint64 spotPrice) internal _spotPrice;

    mapping(address vault => uint64) internal _vaultEquity;

    DoubleEndedQueue.Bytes32Deque internal _withdrawQueue;

    PendingOrder[] internal _pendingOrders;

    EnumerableSet.AddressSet internal _validators;

    mapping(address user => mapping(address vault => uint256 userVaultMultiplier)) internal _userVaultMultiplier;
    mapping(address vault => uint256 multiplier) internal _vaultMultiplier;

    mapping(address user => mapping(address validator => uint256 userStakingYieldIndex)) internal _userStakingYieldIndex;
    uint256 internal _stakingYieldIndex; // assumes same yield for all validators TODO: account for differences due to commissions

    EnumerableSet.Bytes32Set internal _openPerpPositions;

    // Maps user address to a set of perp indices they have active positions in
    mapping(address => EnumerableSet.UintSet) internal _userPerpPositions;

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
        if (_maxLeverage[perp] == 0) {
            if (useRealL1Read) {
              _maxLeverage[perp] = RealL1Read.position(address(1), perp).leverage;
            } else {
              _maxLeverage[perp] = PrecompileLib.position(address(1), perp).leverage;
            }

        }

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

    function setUseRealL1Read(bool _useRealL1Read) public {
        useRealL1Read = _useRealL1Read;
    }

    function _initializeAccountWithToken(address _account, uint64 token) internal {
        _initializeAccount(_account);

        if (_accounts[_account].activated == false) {
            return;
        }

        _initializedSpotBalance[_account][token] = true;
        if (useRealL1Read) {
          _accounts[_account].spot[token] = RealL1Read.spotBalance(_account, token).total;
        } else {
          _accounts[_account].spot[token] = PrecompileLib.spotBalance(_account, token).total;
        }
    }

    function _initializeAccountWithVault(address _account, address _vault) internal {
        _initializedVaults[_account][_vault] = true;
        if (useRealL1Read) {
          _accounts[_account].vaultEquity[_vault] = RealL1Read.userVaultEquity(_account, _vault);
        } else {
          _accounts[_account].vaultEquity[_vault] = PrecompileLib.userVaultEquity(_account, _vault);
        }
    }

    function _initializeAccountWithPerp(address _account, uint16 perp) internal {
        _initializedPerpPosition[_account][perp] = true;
        if (useRealL1Read) {
          _accounts[_account].positions[perp] = RealL1Read.position(_account, perp);
        } else {
          _accounts[_account].positions[perp] = PrecompileLib.position(_account, perp);
        }
    }

    function _initializeAccount(address _account) internal {
        _initializeAccount(_account, false);
    }

    function _initializeAccount(address _account, bool force) internal {
        bool initialized = _initializedAccounts[_account];

        if (initialized) {
            return;
        }

        AccountData storage account = _accounts[_account];

        // check if the acc is created on Core
        RealL1Read.CoreUserExists memory coreUserExists;
        if (useRealL1Read) {
          coreUserExists = RealL1Read.coreUserExists(_account);
        } else {
          coreUserExists.exists = PrecompileLib.coreUserExists(_account);
        }
        if (!coreUserExists.exists && !force) {
            return;
        }

        _initializedAccounts[_account] = true;
        account.activated = true;

        // setting perp balance
        if (useRealL1Read) {
          account.perpBalance = RealL1Read.withdrawable(_account).withdrawable;
        } else {
          account.perpBalance = PrecompileLib.withdrawable(_account);
        }

        // setting staking balance
        PrecompileLib.DelegatorSummary memory summary;
        if (useRealL1Read) {
          summary = RealL1Read.delegatorSummary(_account);
        } else {
          summary = PrecompileLib.delegatorSummary(_account);
        }
        account.staking = summary.undelegated;

        // assume each pending withdrawal is of equal size
        uint64 pendingWithdrawals = summary.nPendingWithdrawals;

        // when handling existing pending withdrawals, we don't have access to granular details on each one
        // so we assume equal size and expiry after 7 days
        if (pendingWithdrawals > 0) {
            // assume that they all expire after 7 days
            uint32 pendingWithdrawalTime = uint32(block.timestamp + 7 days);

            for (uint256 i = 0; i < pendingWithdrawals; i++) {
                uint256 pendingWithdrawalAmount;

                bool last = i == pendingWithdrawals - 1;

                if (!last) {
                    pendingWithdrawalAmount = summary.totalPendingWithdrawal / pendingWithdrawals;
                } else {
                    // ensure that sum(withdrawalAmount) = totalPendingWithdrawal (accounting for precision loss during division)
                    pendingWithdrawalAmount =
                        summary.totalPendingWithdrawal - (summary.totalPendingWithdrawal / pendingWithdrawals) * i;
                }

                // add to withdrawal queue
                _withdrawQueue.pushBack(
                    serializeWithdrawRequest(
                        WithdrawRequest({
                            account: _account,
                            amount: uint64(pendingWithdrawalAmount),
                            lockedUntilTimestamp: pendingWithdrawalTime
                        })
                    )
                );
            }
        }

        // set delegations
        PrecompileLib.Delegation[] memory delegations;
        if (useRealL1Read) {
          delegations = RealL1Read.delegations(_account);
        } else {
          delegations = PrecompileLib.delegations(_account);
        }
        for (uint256 i = 0; i < delegations.length; i++) {
            account.delegations[delegations[i].validator] = delegations[i];
        }

        if (useRealL1Read) {
          _accounts[_account].marginSummary[0] = RealL1Read.accountMarginSummary(0, _account);
        } else {
          _accounts[_account].marginSummary[0] = PrecompileLib.accountMarginSummary(0, _account);
        }
    }

    modifier whenActivated(address sender) {
        if (_accounts[sender].activated == false) {
            return;
        }
        _;
    }

    function registerTokenInfo(uint64 index) public {
        // if the token is already registered, return early
        if (bytes(_tokens[index].name).length > 0) {
            return;
        }

        PrecompileLib.TokenInfo memory tokenInfo;
        if (useRealL1Read) {
          tokenInfo = RealL1Read.tokenInfo(uint32(index));
        } else {
          tokenInfo = PrecompileLib.tokenInfo(uint32(index));
        }

        // this means that the precompile call failed
        if (tokenInfo.evmContract == RealL1Read.INVALID_ADDRESS) return;
        _tokens[index] = tokenInfo;
    }

    // @dev if this set has len > 0, only validators within the set can be delegated to
    function registerValidator(address validator) public {
        _validators.add(validator);
    }

    /// @dev account creation can be forced when there isnt a reliance on testing that workflow.
    function forceAccountActivation(address account) public {
        // force initialize the account
        _initializeAccount(account, true);
        _accounts[account].activated = true;
    }

    function forceSpotBalance(address account, uint64 token, uint64 _wei) public payable {
        if (_accounts[account].activated == false) {
            forceAccountActivation(account);
        }

        if (_initializedSpotBalance[account][token] == false) {
            registerTokenInfo(token);
            _initializeAccountWithToken(account, token);
        }

        _accounts[account].spot[token] = _wei;
    }

    function forcePerpBalance(address account, uint64 usd) public payable {
        if (_accounts[account].activated == false) {
            forceAccountActivation(account);
        }
        if (_initializedAccounts[account] == false) {
            _initializeAccount(account);
        }

        _accounts[account].perpBalance = usd;
    }

    function forceStakingBalance(address account, uint64 _wei) public payable {
        forceAccountActivation(account);
        _accounts[account].staking = _wei;
    }

    function forceDelegation(address account, address validator, uint64 amount, uint64 lockedUntilTimestamp) public {
        forceAccountActivation(account);
        _accounts[account].delegations[validator] =
            PrecompileLib.Delegation({validator: validator, amount: amount, lockedUntilTimestamp: lockedUntilTimestamp});
    }

    function forceVaultEquity(address account, address vault, uint64 usd, uint64 lockedUntilTimestamp) public payable {
        forceAccountActivation(account);

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
