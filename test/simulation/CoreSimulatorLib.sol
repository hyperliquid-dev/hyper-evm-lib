// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm} from "forge-std/Vm.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {HyperCore} from "./HyperCore.sol";
import {CoreWriterSim} from "./CoreWriterSim.sol";
import {PrecompileSim} from "./PrecompileSim.sol";

import {PrecompileLib, HLConstants} from "../../src/PrecompileLib.sol";
import {TokenRegistry} from "../../src/registry/TokenRegistry.sol";

Vm constant vm = Vm(address(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D));
CoreWriterSim constant coreWriter = CoreWriterSim(0x3333333333333333333333333333333333333333);

contract HypeSystemContract {
    receive() external payable {
        coreWriter.nativeTransferCallback{value: msg.value}(msg.sender, msg.sender, msg.value);
    }
}

/**
 * @title CoreSimulatorLib
 * @dev A library used to simulate HyperCore functionality in foundry tests
 */
library CoreSimulatorLib {
    uint256 constant NUM_PRECOMPILES = 17;

    HyperCore constant hyperCore = HyperCore(payable(0x9999999999999999999999999999999999999999));

    // ERC20 Transfer event signature
    bytes32 constant TRANSFER_EVENT_SIG = keccak256("Transfer(address,address,uint256)");

    function init() internal returns (HyperCore) {
        vm.pauseGasMetering();

        HyperCore coreImpl = new HyperCore();

        vm.etch(address(hyperCore), address(coreImpl).code);

        // Setting storage variables at the etched address
        hyperCore.setStakingYieldIndex(1e18);
        hyperCore.setUseRealL1Read(true);
        hyperCore.setSpotMakerFee(400);
        hyperCore.setPerpMakerFee(150);

        vm.etch(address(coreWriter), type(CoreWriterSim).runtimeCode);

        // Initialize precompiles
        for (uint160 i = 0; i < NUM_PRECOMPILES; i++) {
            address precompileAddress = address(uint160(0x0000000000000000000000000000000000000800) + i);
            vm.etch(precompileAddress, type(PrecompileSim).runtimeCode);
            vm.allowCheatcodes(precompileAddress);
        }

        // System addresses
        address hypeSystemAddress = address(0x2222222222222222222222222222222222222222);
        vm.etch(hypeSystemAddress, type(HypeSystemContract).runtimeCode);

        // Start recording logs for token transfer tracking
        vm.recordLogs();

        vm.allowCheatcodes(address(hyperCore));
        vm.allowCheatcodes(address(coreWriter));

        // if offline mode, deploy the TokenRegistry and register main tokens
        if (!isForkActive()) {
            _deployTokenRegistryAndCoreTokens();
        }

        vm.resumeGasMetering();

        return hyperCore;
    }

    function nextBlock(bool expectRevert) internal {
        // Get all recorded logs
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Process any ERC20 transfers to system addresses (EVM->Core transfers are processed before CoreWriter actions)
        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory entry = entries[i];

            // Check if it's a Transfer event
            if (entry.topics[0] == TRANSFER_EVENT_SIG) {
                address from = address(uint160(uint256(entry.topics[1])));
                address to = address(uint160(uint256(entry.topics[2])));
                uint256 amount = abi.decode(entry.data, (uint256));

                // Check if destination is a system address
                if (isSystemAddress(to)) {
                    uint64 tokenIndex = getTokenIndexFromSystemAddress(to);

                    // Call tokenTransferCallback on HyperCoreWrite
                    hyperCore.executeTokenTransfer(address(0), tokenIndex, from, amount);
                }
            }
        }

        // Clear recorded logs for next block
        vm.recordLogs();

        // Advance block
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);

        // liquidate any positions that are liquidatable
        hyperCore.liquidatePositions();

        // Process any pending actions
        coreWriter.executeQueuedActions(expectRevert);

        // Process pending orders
        hyperCore.processPendingOrders();
    }

    function nextBlock() internal {
        nextBlock(false);
    }

    ////// Testing Config Setters /////////

    function setRevertOnFailure(bool _revertOnFailure) internal {
        coreWriter.setRevertOnFailure(_revertOnFailure);
    }

    // cheatcodes //
    function forceAccountActivation(address account) internal {
        hyperCore.forceAccountActivation(account);
    }

    function setOfflineMode(bool isOffline) internal {
        hyperCore.setUseRealL1Read(!isOffline);
        vm.warp(vm.unixTime() / 1e3);
    }

    function forceSpotBalance(address account, uint64 token, uint64 _wei) internal {
        hyperCore.forceSpotBalance(account, token, _wei);
    }

    function forcePerpBalance(address account, uint64 usd) internal {
        hyperCore.forcePerpBalance(account, usd);
    }

    function forceStakingBalance(address account, uint64 _wei) internal {
        hyperCore.forceStakingBalance(account, _wei);
    }

    function forceDelegation(address account, address validator, uint64 amount, uint64 lockedUntilTimestamp) internal {
        hyperCore.forceDelegation(account, validator, amount, lockedUntilTimestamp);
    }

    function forceVaultEquity(address account, address vault, uint64 usd, uint64 lockedUntilTimestamp) internal {
        hyperCore.forceVaultEquity(account, vault, usd, lockedUntilTimestamp);
    }

    function setMarkPx(uint32 perp, uint64 markPx) internal {
        hyperCore.setMarkPx(perp, markPx);
    }

    function setMarkPx(uint32 perp, uint64 priceDiffBps, bool isIncrease) internal {
        hyperCore.setMarkPx(perp, priceDiffBps, isIncrease);
    }

    function setSpotPx(uint32 spotMarketId, uint64 spotPx) internal {
        hyperCore.setSpotPx(spotMarketId, spotPx);
    }

    function setSpotPx(uint32 spotMarketId, uint64 priceDiffBps, bool isIncrease) internal {
        hyperCore.setSpotPx(spotMarketId, priceDiffBps, isIncrease);
    }

    function setVaultMultiplier(address vault, uint64 multiplier) internal {
        hyperCore.setVaultMultiplier(vault, multiplier);
    }

    function setStakingYieldIndex(uint64 multiplier) internal {
        hyperCore.setStakingYieldIndex(multiplier);
    }

    function setSpotMakerFee(uint16 bps) internal {
        hyperCore.setSpotMakerFee(bps);
    }

    function setPerpMakerFee(uint16 bps) internal {
        hyperCore.setPerpMakerFee(bps);
    }

    function forcePerpLeverage(address account, uint16 perp, uint32 leverage) internal {
        hyperCore.forcePerpPositionLeverage(account, perp, leverage);
    }

    ///// Private Functions /////
    function _deployTokenRegistryAndCoreTokens() private {
        TokenRegistry registry = TokenRegistry(0x0b51d1A9098cf8a72C325003F44C194D41d7A85B);
        vm.etch(address(registry), type(TokenRegistry).runtimeCode);

        // register HYPE in hyperCore
        uint64[] memory hypeSpots = new uint64[](3);
        hypeSpots[0] = 107;
        hypeSpots[1] = 207;
        hypeSpots[2] = 232;
        PrecompileLib.TokenInfo memory hypeTokenInfo = PrecompileLib.TokenInfo({
            name: "HYPE",
            spots: hypeSpots,
            deployerTradingFeeShare: 0,
            deployer: address(0),
            evmContract: address(0),
            szDecimals: 2,
            weiDecimals: 8,
            evmExtraWeiDecimals: 0
        });
        hyperCore.registerTokenInfo(150, hypeTokenInfo);

        // register USDC in hyperCore
        uint64[] memory usdcSpots = new uint64[](0);
        PrecompileLib.TokenInfo memory usdcTokenInfo = PrecompileLib.TokenInfo({
            name: "USDC",
            spots: usdcSpots,
            deployerTradingFeeShare: 0,
            deployer: address(0),
            evmContract: address(0),
            szDecimals: 8,
            weiDecimals: 8,
            evmExtraWeiDecimals: 0
        });
        hyperCore.registerTokenInfo(0, usdcTokenInfo);

        // register USDT in hyperCore
        address usdt0 = 0xB8CE59FC3717ada4C02eaDF9682A9e934F625ebb;

        Token usdt0Token = new Token();
        vm.etch(usdt0, address(usdt0Token).code);

        uint64[] memory usdt0Spots = new uint64[](1);
        usdt0Spots[0] = 166;
        PrecompileLib.TokenInfo memory usdtTokenInfo = PrecompileLib.TokenInfo({
            name: "USDT0",
            spots: usdt0Spots,
            deployerTradingFeeShare: 0,
            deployer: 0x1a6362AD64ccFF5902D46D875B36e8798267d154,
            evmContract: usdt0,
            szDecimals: 2,
            weiDecimals: 8,
            evmExtraWeiDecimals: -2
        });
        hyperCore.registerTokenInfo(268, usdtTokenInfo);
        registry.setTokenInfo(268);

        // register spot markets
        PrecompileLib.SpotInfo memory hypeSpotInfo =
            PrecompileLib.SpotInfo({name: "@107", tokens: [uint64(150), uint64(0)]});
        hyperCore.registerSpotInfo(107, hypeSpotInfo);

        PrecompileLib.SpotInfo memory usdt0SpotInfo =
            PrecompileLib.SpotInfo({name: "@166", tokens: [uint64(268), uint64(0)]});
        hyperCore.registerSpotInfo(166, usdt0SpotInfo);

        // register HYPE perp info
        PrecompileLib.PerpAssetInfo memory hypePerpAssetInfo = PrecompileLib.PerpAssetInfo({
            coin: "HYPE", marginTableId: 52, szDecimals: 2, maxLeverage: 10, onlyIsolated: false
        });
        hyperCore.registerPerpAssetInfo(150, hypePerpAssetInfo);
    }

    ///// VIEW AND PURE /////////

    function isSystemAddress(address addr) internal view returns (bool) {
        // Check if it's the HYPE system address
        if (addr == address(0x2222222222222222222222222222222222222222)) {
            return true;
        }

        // Check if it's a token system address (0x2000...0000 + index)
        uint160 baseAddr = uint160(0x2000000000000000000000000000000000000000);
        uint160 addrInt = uint160(addr);

        if (addrInt >= baseAddr && addrInt < baseAddr + 10000) {
            uint64 tokenIndex = uint64(addrInt - baseAddr);

            if (tokenExists(tokenIndex)) {
                return true;
            } else {
                revert("Bridging failed: Corresponding token not found on HyperCore");
            }
        }

        return false;
    }

    function getTokenIndexFromSystemAddress(address systemAddr) internal pure returns (uint64) {
        if (systemAddr == address(0x2222222222222222222222222222222222222222)) {
            return 150; // HYPE token index
        }

        if (uint160(systemAddr) < uint160(0x2000000000000000000000000000000000000000)) return type(uint64).max;

        return uint64(uint160(systemAddr) - uint160(0x2000000000000000000000000000000000000000));
    }

    function tokenExists(uint64 token) internal view returns (bool) {
        (bool success,) = HLConstants.TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(token));
        return success;
    }

    /// @dev Make an address persistent to prevent RPC storage calls
    /// Call this for any test addresses you create/etch to prevent RPC calls
    function makeAddressPersistent(address addr) internal {
        vm.makePersistent(addr);
        vm.deal(addr, 1 wei); // Ensure it "exists" in the fork
    }

    function isForkActive() internal view returns (bool) {
        try vm.activeFork() returns (uint256) {
            return true; // Fork is active
        } catch {
            return false; // No fork active
        }
    }
}

contract Token is ERC20 {
    constructor() ERC20("USDT0", "USDT0") {}
}
