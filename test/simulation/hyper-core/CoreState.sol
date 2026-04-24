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
    uint256 public constant FEE_DENOMINATOR = 1e6;

    // Default taker fees for simulator-controlled spot/perp trades (100% = 1e6)
    uint16 public spotMakerFee;
    uint16 public perpMakerFee;

    constructor() {
        HYPE_TOKEN_INDEX = HLConstants.hypeTokenIndex();
    }

    /// @dev Seeds the known HIP-3 dex → quote token mappings and the corresponding
    /// _isQuoteToken flags. Called from CoreSimulatorLib.init() after `vm.etch`
    /// (which copies runtime code only, so the constructor can't seed storage).
    /// Tests can extend via registerDexQuoteToken.
    function seedDexQuoteTokenRegistry() public {
        _registerDexQuoteToken(0, 0);     // default dex: USDC
        _registerDexQuoteToken(1, 0);     // HIP-3 USDC-collateralized (e.g. xyz stock perps)
        _registerDexQuoteToken(2, 360);   // HIP-3 USDH-collateralized
        _registerDexQuoteToken(3, 360);   // HIP-3 USDH-collateralized
        _registerDexQuoteToken(4, 235);   // HIP-3 USDE-collateralized
        _registerDexQuoteToken(5, 360);   // HIP-3 USDH-collateralized
        _registerDexQuoteToken(6, 0);     // HIP-3 USDC-collateralized
        _registerDexQuoteToken(7, 268);   // HIP-3 USDT0-collateralized
    }

    function _registerDexQuoteToken(uint32 dex, uint64 token) private {
        _dexQuoteToken[dex] = token;
        _dexRegistered[dex] = true;
        _isQuoteToken[token] = true;
    }

    /// @notice Register or override the collateral token for a perp dex. Keeps _isQuoteToken in sync.
    function registerDexQuoteToken(uint32 dex, uint64 token) public {
        _registerDexQuoteToken(dex, token);
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
        uint64 staking; // undelegated staking balance
        EnumerableSet.AddressSet delegatedValidators;
        mapping(address validator => PrecompileLib.Delegation) delegations;
        mapping(uint32 dex => uint64) perpBalance;
        mapping(uint32 perpIndex => PrecompileLib.Position) positions;
        mapping(uint32 dex => mapping(uint32 perpIndex => uint64)) margin;
        mapping(uint32 dex => PrecompileLib.AccountMarginSummary) marginSummary;
    }

    struct PendingOrder {
        address sender;
        LimitOrderAction action;
    }

    // Whether to use real L1 read or not
    bool public useRealL1Read;

    // registered token info
    mapping(uint64 token => PrecompileLib.TokenInfo) internal _tokens;
    mapping(uint32 perp => PrecompileLib.PerpAssetInfo) internal _perpAssetInfo;
    mapping(uint32 spot => PrecompileLib.SpotInfo) internal _spotInfo;

    mapping(address account => AccountData) internal _accounts;

    mapping(address account => bool initialized) internal _initializedAccounts;
    mapping(address account => mapping(uint64 token => bool initialized)) internal _initializedSpotBalance;
    mapping(address account => mapping(address vault => bool initialized)) internal _initializedVaults;

    mapping(address account => mapping(uint32 perpIndex => bool initialized)) internal _initializedPerpPosition;

    mapping(address account => mapping(uint64 token => uint64 latentBalance)) internal _latentSpotBalance;

    mapping(uint32 perpIndex => uint64 markPrice) internal _perpMarkPrice;
    mapping(uint32 perpIndex => uint64 oraclePrice) internal _perpOraclePrice;
    mapping(uint32 spotMarketId => uint64 spotPrice) internal _spotPrice;

    mapping(address vault => uint64) internal _vaultEquity;

    DoubleEndedQueue.Bytes32Deque internal _withdrawQueue;

    PendingOrder[] internal _pendingOrders;

    EnumerableSet.AddressSet internal _validators;

    mapping(address user => mapping(address vault => uint256 userVaultMultiplier)) internal _userVaultMultiplier;
    mapping(address vault => uint256 multiplier) internal _vaultMultiplier;

    mapping(address user => mapping(address validator => uint256 userStakingYieldIndex)) internal
        _userStakingYieldIndex;
    uint256 internal _stakingYieldIndex; // assumes same yield for all validators TODO: account for differences due to commissions

    mapping(uint32 dex => EnumerableSet.Bytes32Set) internal _openPerpPositions;

    // Maps user address to a set of perp indices they have active positions in (per-dex)
    mapping(uint32 dex => mapping(address => EnumerableSet.UintSet)) internal _userPerpPositions;

    mapping(uint64 token => bool isQuoteToken) internal _isQuoteToken;

    // Per-(user, dex) flag: true once the sim has taken over state for this dex.
    // Reads for untouched dexes fall through to RealL1Read.
    mapping(address account => mapping(uint32 dex => bool initialized)) internal _initializedDexBalance;

    // Dex → collateral/quote token registry. Storage-backed so tests can extend.
    mapping(uint32 dex => uint64 quoteToken) internal _dexQuoteToken;
    mapping(uint32 dex => bool registered) internal _dexRegistered;

    // Cache: did the account exist on chain at initialization time? Used to skip
    // redundant RPC calls in HIP-3 read/write paths for force-activated test users
    // that were never on chain.
    mapping(address account => bool existedOnChain) internal _chainAccountExisted;
    mapping(address account => bool checked) internal _chainAccountExistedChecked;



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

    modifier initAccountWithPerp(address _account, uint32 perp) {
        if (_perpAssetInfo[perp].maxLeverage == 0) {
            registerPerpAssetInfo(perp, RealL1Read.perpAssetInfo(perp));
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

    function setSpotMakerFee(uint16 bps) public {
        require(bps <= FEE_DENOMINATOR, "fee too high");
        spotMakerFee = bps;
    }

    function setPerpMakerFee(uint16 bps) public {
        require(bps <= FEE_DENOMINATOR, "fee too high");
        perpMakerFee = bps;
    }

    function _initializeAccountWithToken(address _account, uint64 token) internal {
        _initializeAccount(_account);

        if (_accounts[_account].activated == false) {
            return;
        }

        _initializedSpotBalance[_account][token] = true;
        _accounts[_account].spot[token] = RealL1Read.spotBalance(_account, token).total;
    }

    function _initializeAccountWithVault(address _account, address _vault) internal {
        _initializedVaults[_account][_vault] = true;
        _accounts[_account].vaultEquity[_vault] = RealL1Read.userVaultEquity(_account, _vault);
    }

    function _initializeAccountWithPerp(address _account, uint32 perp) internal {
        _initializedPerpPosition[_account][perp] = true;
        _accounts[_account].positions[perp] = RealL1Read.position(_account, perp);
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
        bool coreUserExists = RealL1Read.coreUserExists(_account);
        _chainAccountExisted[_account] = coreUserExists;
        _chainAccountExistedChecked[_account] = true;
        if (!coreUserExists && !force) {
            return;
        }

        _initializedAccounts[_account] = true;
        account.activated = true;

        // setting perp balance for default dex (uses withdrawable precompile only
        // if the user actually existed on chain; otherwise default to 0)
        account.perpBalance[HLConstants.DEFAULT_PERP_DEX] =
            coreUserExists ? RealL1Read.withdrawable(_account) : 0;
        _initializedDexBalance[_account][HLConstants.DEFAULT_PERP_DEX] = true;

        // HIP-3 dex balances are seeded lazily on first touch via _initializeDex.
        // This avoids (a) fabricating balances for accounts that never use HIP-3 dexes,
        // (b) inflating seeds with accountValue (which includes locked margin + uPnL),
        // and (c) the brittle hardcoded dex list.

        // setting staking balance (skip RPC for force-activated test accounts
        // that never existed on chain — they can't have staking state)
        PrecompileLib.DelegatorSummary memory summary;
        if (coreUserExists) {
            summary = RealL1Read.delegatorSummary(_account);
            account.staking = summary.undelegated;
        }

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

        // set delegations (only if the account actually exists on chain)
        if (coreUserExists) {
            PrecompileLib.Delegation[] memory delegations = RealL1Read.delegations(_account);
            for (uint256 i = 0; i < delegations.length; i++) {
                account.delegations[delegations[i].validator] = delegations[i];
                account.delegatedValidators.add(delegations[i].validator);
            }

            account.marginSummary[0] = RealL1Read.accountMarginSummary(0, _account);
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
        tokenInfo = RealL1Read.tokenInfo(uint32(index));

        // this means that the precompile call failed
        if (tokenInfo.evmContract == RealL1Read.INVALID_ADDRESS) return;
        _tokens[index] = tokenInfo;

        // _isQuoteToken is now seeded in the constructor via _seedDexQuoteTokenRegistry
        // (which already covers USDC=0, USDH=360, USDE=235, USDT0=268).
    }

    function registerTokenInfo(uint64 index, PrecompileLib.TokenInfo memory tokenInfo) public {
        _tokens[index] = tokenInfo;
    }

    function registerSpotInfo(uint32 spotIndex, PrecompileLib.SpotInfo memory spotInfo) public {
        _spotInfo[spotIndex] = spotInfo;
    }

    function registerPerpAssetInfo(uint32 perpIndex, PrecompileLib.PerpAssetInfo memory perpAssetInfo) public {
        _perpAssetInfo[perpIndex] = perpAssetInfo;
    }

    function perpDex(uint32 perpIndex) internal pure returns (uint32) {
        return perpIndex / 10000;
    }

    /// @dev Converts an asset ID to a perp index for precompile calls
    /// Native perps: asset ID == perp index (e.g. BTC = 0)
    /// HIP-3 perps: asset ID = 100000 + dex * 10000 + index, perp index = dex * 10000 + index
    function assetToPerpIndex(uint32 asset) internal pure returns (uint32) {
        if (asset >= 100000) {
            return asset - 100000;
        }
        return asset;
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
        forcePerpBalance(account, HLConstants.DEFAULT_PERP_DEX, usd);
    }

    function forcePerpBalance(address account, uint32 dex, uint64 usd) public payable {
        if (_accounts[account].activated == false) {
            forceAccountActivation(account);
        }
        if (_initializedAccounts[account] == false) {
            _initializeAccount(account);
        }

        _accounts[account].perpBalance[dex] = usd;
        _initializedDexBalance[account][dex] = true;
    }

    /// @dev Lazy per-(user, dex) initializer. Seeds perpBalance[dex] with an
    /// approximation of withdrawable derived from accountMarginSummary.
    /// For the default dex we use the dedicated `withdrawable` precompile.
    /// For HIP-3 dexes there is no such precompile, so we use:
    ///     withdrawable ≈ max(0, accountValue − max(marginUsed, ntlPos/10))
    /// This mirrors the simulator's own `_previewWithdrawable` formula collapsed
    /// to totals. Exact for flat users and for positions with leverage ≤ 10
    /// (covers typical HIP-3 stock-perp configurations); slightly over-estimates
    /// only for high-leverage HIP-3 positions.
    function _initializeDex(address user, uint32 dex) internal {
        if (_initializedDexBalance[user][dex]) return;
        _initializedDexBalance[user][dex] = true;

        if (_accounts[user].activated == false) return;

        // Users that never existed on chain can't have HIP-3 state; skip RPC.
        if (_chainAccountExistedChecked[user] && !_chainAccountExisted[user]) {
            _accounts[user].perpBalance[dex] = 0;
            return;
        }

        if (dex == HLConstants.DEFAULT_PERP_DEX) {
            _accounts[user].perpBalance[dex] = RealL1Read.withdrawable(user);
            return;
        }

        PrecompileLib.AccountMarginSummary memory ms = RealL1Read.accountMarginSummary(dex, user);
        uint64 transferReq = ms.marginUsed;
        uint64 floor = ms.ntlPos / 10;
        if (floor > transferReq) transferReq = floor;

        if (ms.accountValue > int64(transferReq)) {
            _accounts[user].perpBalance[dex] = uint64(ms.accountValue - int64(transferReq));
        } else {
            _accounts[user].perpBalance[dex] = 0;
        }
    }

    function forcePerpPositionLeverage(address account, uint32 perp, uint32 leverage) public payable {
        if (_accounts[account].activated == false) {
            forceAccountActivation(account);
        }
        if (_initializedPerpPosition[account][perp] == false) {
            _initializeAccountWithPerp(account, perp);
        }

        _accounts[account].positions[perp].leverage = leverage;
    }

    function forceStakingBalance(address account, uint64 _wei) public payable {
        forceAccountActivation(account);
        _accounts[account].staking = _wei;
    }

    function forceDelegation(address account, address validator, uint64 amount, uint64 lockedUntilTimestamp) public {
        forceAccountActivation(account);
        _accounts[account].delegations[validator] = PrecompileLib.Delegation({
            validator: validator, amount: amount, lockedUntilTimestamp: lockedUntilTimestamp
        });
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
            : evmExtraWeiDecimals > 0
                ? _wei * 10 ** uint8(evmExtraWeiDecimals)
                : _wei / 10 ** uint8(-evmExtraWeiDecimals);
    }

    function fromPerp(uint64 usd) internal pure returns (uint64) {
        return usd * 1e2;
    }

    function dexCollateralToken(uint32 dex) internal view returns (uint64) {
        require(_dexRegistered[dex], "dex not registered - call registerDexQuoteToken");
        return _dexQuoteToken[dex];
    }

    // converting a withdraw request into a bytes32
    function serializeWithdrawRequest(CoreState.WithdrawRequest memory request) internal pure returns (bytes32) {
        return bytes32(
            (uint256(uint160(request.account)) << 96) | (uint256(request.amount) << 32)
                | uint40(request.lockedUntilTimestamp)
        );
    }

    function deserializeWithdrawRequest(bytes32 data) internal pure returns (CoreState.WithdrawRequest memory request) {
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

    struct SendAssetAction {
        address destination;
        address subAccount;
        uint32 source_dex;
        uint32 destination_dex;
        uint64 token;
        uint64 amountWei;
    }

    struct UsdClassTransferAction {
        uint64 ntl;
        bool toPerp;
    }
}
