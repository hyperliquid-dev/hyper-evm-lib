// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeCast } from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { DoubleEndedQueue } from "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";
import { Heap } from "@openzeppelin/contracts/utils/structs/Heap.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {PrecompileLib} from "src/PrecompileLib.sol";
import {HLConstants} from "src/CoreWriterLib.sol";
import { console } from "forge-std/console.sol";

import {Vm} from "forge-std/Vm.sol";


uint64 constant KNOWN_TOKEN_USDC = 0;
uint64 constant KNOWN_TOKEN_HYPE = 150;
Vm constant vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);


/// Modified from https://github.com/ambitlabsxyz/hypercore
contract HyperCoreState {
  using Address for address payable;
  using SafeCast for uint256;
  using EnumerableSet for EnumerableSet.AddressSet;
  using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;
  using Heap for Heap.Uint256Heap;

  mapping(uint64 token => PrecompileLib.TokenInfo) private _tokens;

  struct WithdrawRequest {
    address account;
    uint64 amount;
    uint32 lockedUntilTimestamp;
  }

  struct Account {
    bool created;
    uint64 perp;
    mapping(uint64 => uint64) spot;
    mapping(address vault => PrecompileLib.UserVaultEquity) vaultEquity;
    uint64 staking;
    mapping(address validator => PrecompileLib.Delegation) delegations;
  }

  mapping(address account => Account) private _accounts;

  mapping(address vault => uint64) private _vaultEquity;

  DoubleEndedQueue.Bytes32Deque private _withdrawQueue;

  EnumerableSet.AddressSet private _validators;

  constructor() {
    registerTokenInfo(
      KNOWN_TOKEN_HYPE,
      PrecompileLib.TokenInfo({
        name: "HYPE",
        spots: new uint64[](0),
        deployerTradingFeeShare: 0,
        deployer: address(0),
        evmContract: address(0),
        szDecimals: 2,
        weiDecimals: 8,
        evmExtraWeiDecimals: 0
      })
    );
  }

  receive() external payable {}

  modifier whenAccountCreated(address sender) {
    if (_accounts[sender].created == false) {
      return;
    }
    _;
  }

  function registerTokenInfo(uint64 index, PrecompileLib.TokenInfo memory tokenInfo) public {
    // TODO: this can be done with precompiles, not manual
    require(bytes(_tokens[index].name).length == 0);
    require(tokenInfo.evmContract == address(0));

    _tokens[index] = tokenInfo;
  }

  function registerValidator(address validator) public {
    _validators.add(validator);
  }

  /// @dev account creation can be forced when there isnt a reliance on testing that workflow.
  function forceAccountCreation(address account) public {
    _accounts[account].created = true;
  }
  function coreUserExists(address account) public view returns (bool) {
    return _accounts[account].created;
  }

  function forceSpot(address account, uint64 token, uint64 _wei) public payable {
    forceAccountCreation(account);
    _accounts[account].spot[token] = _wei;
  }

  function forcePerp(address account, uint64 usd) public payable {
    forceAccountCreation(account);
    _accounts[account].perp = usd;
  }

  function forceStaking(address account, uint64 _wei) public payable {
    forceAccountCreation(account);
    _accounts[account].staking = _wei;
  }

  function forceDelegation(address account, address validator, uint64 amount, uint64 lockedUntilTimestamp) public {
    forceAccountCreation(account);
    _accounts[account].delegations[validator] = PrecompileLib.Delegation({
      validator: validator,
      amount: amount,
      lockedUntilTimestamp: lockedUntilTimestamp
    });
  }

  function forceVaultEquity(address account, address vault, uint64 usd, uint64 lockedUntilTimestamp) public payable {
    forceAccountCreation(account);

    _vaultEquity[vault] -= _accounts[account].vaultEquity[vault].equity;
    _vaultEquity[vault] += usd;

    _accounts[account].vaultEquity[vault].equity = usd;
    _accounts[account].vaultEquity[vault].lockedUntilTimestamp = lockedUntilTimestamp > 0
      ? lockedUntilTimestamp
      : uint64((block.timestamp + 3600) * 1000);
  }

  function tokenExists(uint64 token) private view returns (bool) {
    return bytes(_tokens[token].name).length > 0;
  }

  /// @dev unstaking takes 7 days and after which it will automatically appear in the users
  /// spot balance so we need to check this at the end of each operation to simulate that.
  function flushCWithdrawQueue() public {
    while (_withdrawQueue.length() > 0) {
      WithdrawRequest memory request = deserializeWithdrawRequest(_withdrawQueue.front());

      if (request.lockedUntilTimestamp > block.timestamp) {
        break;
      }

      _withdrawQueue.popFront();

      _accounts[request.account].spot[KNOWN_TOKEN_HYPE] += request.amount;
    }
  }

  function executeTokenTransfer(
    address,
    uint64 token,
    address from,
    uint256 value
  ) public payable whenAccountCreated(from) {
    _accounts[from].spot[token] += toWei(value, _tokens[token].evmExtraWeiDecimals);
  }

  //TODO: currently if accountCreated==false, then it wont increment balance. but then even once its activated, the funds are lost. instead- the funds should be simply hidden and unusable until the account is created.
  //@i have a new mapping for waiting balances, which is set to the real balance once the account is created
  function executeNativeTransfer(address, address from, uint256 value) public payable whenAccountCreated(from) {
    _accounts[from].spot[KNOWN_TOKEN_HYPE] += (value / 1e10).toUint64();
  }

  function executeRawAction(address sender, uint24 kind, bytes calldata data) public payable {
    if (kind == HLConstants.LIMIT_ORDER_ACTION) {
      //executeLimitOrder(sender, abi.decode(data, (LimitOrderAction)));
      return;
    }

    if (kind == HLConstants.VAULT_TRANSFER_ACTION) {
      executeVaultTransfer(sender, abi.decode(data, (VaultTransferAction)));
      return;
    }

    if (kind == HLConstants.TOKEN_DELEGATE_ACTION) {
      executeTokenDelegate(sender, abi.decode(data, (TokenDelegateAction)));
      return;
    }

    if (kind == HLConstants.STAKING_DEPOSIT_ACTION) {
      executeStakingDeposit(sender, abi.decode(data, (StakingDepositAction)));
      return;
    }

    if (kind == HLConstants.STAKING_WITHDRAW_ACTION) {
      executeStakingWithdraw(sender, abi.decode(data, (StakingWithdrawAction)));
      return;
    }

    if (kind == HLConstants.SPOT_SEND_ACTION) {
      executeSpotSend(sender, abi.decode(data, (SpotSendAction)));
      return;
    }

    if (kind == HLConstants.USD_CLASS_TRANSFER_ACTION) {
      executeUsdClassTransfer(sender, abi.decode(data, (UsdClassTransferAction)));
      return;
    }
  }

  function executeSpotSend(
    address sender,
    SpotSendAction memory action
  ) private whenAccountCreated(sender) {
    if (action._wei > _accounts[sender].spot[action.token]) {
      return;
    }

    _accounts[sender].spot[action.token] -= action._wei;

    address systemAddress = action.token == 150
      ? 0x2222222222222222222222222222222222222222
      : address(uint160(address(0x2000000000000000000000000000000000000000)) + action.token);

    if (action.destination == systemAddress) {

      if (action.token == KNOWN_TOKEN_HYPE) {
        vm.prank(systemAddress);
        payable(sender).sendValue(action._wei * 1e10);
        return;
      }

      // TODO: this requires HYPE balance to pay some gas for the transfer
      vm.prank(systemAddress);
      IERC20(_tokens[action.token].evmContract).transfer(action.destination, fromWei(action._wei, _tokens[action.token].evmExtraWeiDecimals));
      return;
    }

    _accounts[action.destination].spot[action.token] += action._wei;

    if (_accounts[action.destination].created == false) {
      // TODO: this should deduct 1 USDC from the sender in order to create the destination
      _accounts[action.destination].created = true;
    }
  }

  function executeUsdClassTransfer(
    address sender,
    UsdClassTransferAction memory action
  ) private whenAccountCreated(sender) {
    if (action.toPerp) {
      if (fromPerp(action.ntl) <= _accounts[sender].spot[KNOWN_TOKEN_USDC]) {
        _accounts[sender].perp += action.ntl;
        _accounts[sender].spot[KNOWN_TOKEN_USDC] -= fromPerp(action.ntl);
      }
    } else {
      if (action.ntl <= _accounts[sender].perp) {
        _accounts[sender].perp -= action.ntl;
        _accounts[sender].spot[KNOWN_TOKEN_USDC] += fromPerp(action.ntl);
      }
    }
  }

  function executeVaultTransfer(
    address sender,
    VaultTransferAction memory action
  ) private whenAccountCreated(sender) {
    if (action.isDeposit) {
      if (action.usd <= _accounts[sender].perp) {
        _accounts[sender].vaultEquity[action.vault].equity += action.usd;
        _accounts[sender].vaultEquity[action.vault].lockedUntilTimestamp = uint64((block.timestamp + 3600) * 1000);
        _accounts[sender].perp -= action.usd;
        _vaultEquity[action.vault] += action.usd;
      }
    } else {
      PrecompileLib.UserVaultEquity storage userVaultEquity = _accounts[sender].vaultEquity[action.vault];

      // a zero amount means withdraw the entire amount
      action.usd = action.usd == 0 ? userVaultEquity.equity : action.usd;

      // the vaults have a minimum withdraw of 1 / 100,000,000
      if (action.usd < _vaultEquity[action.vault] / 1e8) {
        return;
      }

      if (action.usd <= userVaultEquity.equity && userVaultEquity.lockedUntilTimestamp / 1000 <= block.timestamp) {
        userVaultEquity.equity -= action.usd;
        _accounts[sender].perp += action.usd;
      }
    }
  }

  function executeStakingDeposit(
    address sender,
    StakingDepositAction memory action
  ) private whenAccountCreated(sender) {
    if (action._wei <= _accounts[sender].spot[KNOWN_TOKEN_HYPE]) {
      _accounts[sender].spot[KNOWN_TOKEN_HYPE] -= action._wei;
      _accounts[sender].staking += action._wei;
    }
  }

  function executeStakingWithdraw(
    address sender,
    StakingWithdrawAction memory action
  ) private whenAccountCreated(sender) {
    if (action._wei <= _accounts[sender].staking) {
      _accounts[sender].staking -= action._wei;

      WithdrawRequest memory withrawRequest = WithdrawRequest({
        account: sender,
        amount: action._wei,
        lockedUntilTimestamp: uint32(block.timestamp + 7 days)
      });

      _withdrawQueue.pushBack(serializeWithdrawRequest(withrawRequest));
    }
  }

  function executeTokenDelegate(address sender, TokenDelegateAction memory action) private {
    require(_validators.contains(action.validator));

    if (action.isUndelegate) {
      PrecompileLib.Delegation storage delegation = _accounts[sender].delegations[action.validator];
      if (action._wei <= delegation.amount && block.timestamp * 1000 > delegation.lockedUntilTimestamp) {
        _accounts[sender].staking += action._wei;
        delegation.amount -= action._wei;
      }
    } else {
      if (action._wei <= _accounts[sender].staking) {
        _accounts[sender].staking -= action._wei;
        _accounts[sender].delegations[action.validator].amount += action._wei;
        _accounts[sender].delegations[action.validator].lockedUntilTimestamp = ((block.timestamp + 84600) * 1000)
          .toUint64();
      }
    }
  }

  function readTokenInfo(uint32 token) public view returns (PrecompileLib.TokenInfo memory) {
    require(tokenExists(token));
    return _tokens[token];
  }

  function readSpotBalance(address account, uint64 token) public view returns (PrecompileLib.SpotBalance memory) {
    //require(tokenExists(token));
    return PrecompileLib.SpotBalance({ total: _accounts[account].spot[token], entryNtl: 0, hold: 0 });
  }

  function readWithdrawable(address account) public view returns (PrecompileLib.Withdrawable memory) {
    return PrecompileLib.Withdrawable({ withdrawable: _accounts[account].perp });
  }

  function readUserVaultEquity(address user, address vault) public view returns (PrecompileLib.UserVaultEquity memory) {
    return _accounts[user].vaultEquity[vault];
  }

  function readDelegation(
    address user,
    address validator
  ) public view returns (PrecompileLib.Delegation memory delegation) {
    delegation.validator = validator;
    delegation.amount = _accounts[user].delegations[validator].amount;
    delegation.lockedUntilTimestamp = _accounts[user].delegations[validator].lockedUntilTimestamp;
  }

  function readDelegations(address user) public view returns (PrecompileLib.Delegation[] memory userDelegations) {
    address[] memory validators = _validators.values();

    userDelegations = new PrecompileLib.Delegation[](validators.length);
    for (uint256 i; i < userDelegations.length; i++) {
      userDelegations[i].validator = validators[i];

      PrecompileLib.Delegation memory delegation = _accounts[user].delegations[validators[i]];
      userDelegations[i].amount = delegation.amount;
      userDelegations[i].lockedUntilTimestamp = delegation.lockedUntilTimestamp;
    }
  }

  function readDelegatorSummary(address user) public view returns (PrecompileLib.DelegatorSummary memory summary) {
    address[] memory validators = _validators.values();

    for (uint256 i; i < validators.length; i++) {
      PrecompileLib.Delegation memory delegation = _accounts[user].delegations[validators[i]];
      summary.delegated += delegation.amount;
    }

    summary.undelegated = _accounts[user].staking;

    for (uint256 i; i < _withdrawQueue.length(); i++) {
      WithdrawRequest memory request = deserializeWithdrawRequest(_withdrawQueue.at(i));
      if (request.account == user) {
        summary.nPendingWithdrawals++;
        summary.totalPendingWithdrawal += request.amount;
      }
    }
  }

  function readPosition(address user, uint16 perp) public view returns (PrecompileLib.Position memory) {
    // TODO
  }

  function toWei(uint256 amount, int8 evmExtraWeiDecimals) private pure returns (uint64) {
    uint256 _wei = evmExtraWeiDecimals == 0 ? amount : evmExtraWeiDecimals > 0
      ? amount / 10 ** uint8(evmExtraWeiDecimals)
      : amount * 10 ** uint8(-evmExtraWeiDecimals);

    return _wei.toUint64();
  }

  function fromWei(uint64 _wei, int8 evmExtraWeiDecimals) private pure returns (uint256) {
    return
      evmExtraWeiDecimals == 0 ? _wei : evmExtraWeiDecimals > 0
        ? _wei * 10 ** uint8(evmExtraWeiDecimals)
        : _wei / 10 ** uint8(-evmExtraWeiDecimals);
  }

  function fromPerp(uint64 usd) private pure returns (uint64) {
    return usd * 1e2;
  }
  

  // converting a withdraw request into a bytes32
  function serializeWithdrawRequest(HyperCoreState.WithdrawRequest memory request) internal pure returns (bytes32) {
    return
      bytes32(
        (uint256(uint160(request.account)) << 96) |
          (uint256(request.amount) << 32) |
          uint40(request.lockedUntilTimestamp)
      );
  }

  function deserializeWithdrawRequest(bytes32 data) internal pure returns (HyperCoreState.WithdrawRequest memory request) {
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
