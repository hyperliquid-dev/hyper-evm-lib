// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CoreWriterLib, HLConstants, HLConversions} from "@hyper-evm-lib/src/CoreWriterLib.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";

/**
 * @title BridgingExample
 * @dev This contract demonstrates CoreWriterLib bridging functionality.
 * Provides examples for bridging tokens between EVM and Core using both
 * token IDs and token addresses.
 */
contract BridgingExample {
    using CoreWriterLib for *;

    /*//////////////////////////////////////////////////////////////
                        EVM to Core Bridging
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bridges tokens from EVM to Core using token ID
     */
    function bridgeToCoreById(uint64 tokenId, uint256 evmAmount) external payable {
        // Bridge tokens to core using token ID
        CoreWriterLib.bridgeToCore(tokenId, evmAmount);
    }

    /**
     * @notice Bridges tokens from EVM to Core using token address
     */
    function bridgeToCoreByAddress(address tokenAddress, uint256 evmAmount) external payable {
        // Bridge tokens to core using token address
        CoreWriterLib.bridgeToCore(tokenAddress, evmAmount);
    }

    /**
     * @notice Bridges USDC from EVM to Core for a specific recipient
     * @param recipient The address that will receive the USDC on Core
     * @param evmAmount The amount of USDC to bridge (in EVM decimals)
     */
    function bridgeUsdcToCoreTo(address recipient, uint256 evmAmount) external payable {
        // Bridge USDC to core for a specific recipient
        CoreWriterLib.bridgeUsdcToCoreTo(recipient, evmAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        Core to EVM Bridging
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bridges tokens from Core to EVM using token ID
     */
    function bridgeToEvmById(uint64 tokenId, uint256 evmAmount) external {
        // Bridge tokens from core to EVM using token ID
        // Note: For non-HYPE tokens, the contract must hold some HYPE on core for gas
        CoreWriterLib.bridgeToEvm(tokenId, evmAmount, true);
    }

    /**
     * @notice Bridges tokens from Core to EVM using token address
     */
    function bridgeToEvmByAddress(address tokenAddress, uint256 evmAmount) external {
        // Bridge tokens from core to EVM using token address
        // Note: For non-HYPE tokens, the contract must hold some HYPE on core for gas
        CoreWriterLib.bridgeToEvm(tokenAddress, evmAmount);
    }

    /**
     * @notice Bridges HYPE tokens from Core to EVM
     * @param evmAmount Amount of HYPE tokens to bridge (in EVM decimals)
     */
    function bridgeHypeToEvm(uint256 evmAmount) external {
        // Bridge HYPE tokens from core to EVM
        CoreWriterLib.bridgeToEvm(HLConstants.hypeTokenIndex(), evmAmount, true);
    }

    /*//////////////////////////////////////////////////////////////
                        Advanced Bridging Example
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Bridges tokens to core and then sends them to another address
     */
    function bridgeToCoreAndSend(address tokenAddress, uint256 evmAmount, address recipient) external payable {
        // Get token ID from address
        uint64 tokenId = PrecompileLib.getTokenIndex(tokenAddress);

        // Bridge tokens to core
        CoreWriterLib.bridgeToCore(tokenAddress, evmAmount);

        // Convert EVM amount to core amount
        uint64 coreAmount = HLConversions.evmToWei(tokenId, evmAmount);

        // Send tokens to recipient on core
        CoreWriterLib.spotSend(recipient, tokenId, coreAmount);
    }

    function bridgeToCoreAndSendHype(uint256 evmAmount, address recipient) external payable {
        // Bridge tokens to core
        CoreWriterLib.bridgeToCore(HLConstants.hypeTokenIndex(), evmAmount);

        // Convert EVM amount to core amount
        uint64 coreAmount = HLConversions.evmToWei(HLConstants.hypeTokenIndex(), evmAmount);

        // Send tokens to recipient on core
        CoreWriterLib.spotSend(recipient, HLConstants.hypeTokenIndex(), coreAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        Utility Functions
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the token index for a given token address
     */
    function getTokenIndex(address tokenAddress) external view returns (uint64 tokenId) {
        return PrecompileLib.getTokenIndex(tokenAddress);
    }

    receive() external payable {}
}
