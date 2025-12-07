// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title TokenRegistry v1.0
 * @author Obsidian (https://x.com/ObsidianAudits)
 * @notice A trustless, onchain record of Hyperliquid token indices for each linked evm contract
 * @dev Data is sourced solely from the respective precompiles
 */
contract TokenRegistry {
    address constant TOKEN_INFO_PRECOMPILE_ADDRESS = 0x000000000000000000000000000000000000080C;
    address constant USDC_EVM_CONTRACT_ADDRESS = 0xb88339CB7199b77E23DB6E890353E22632Ba630f;

    /// @notice Maps evm contract addresses to their HyperCore token index
    mapping(address => TokenData) internal addressToIndex;

    /**
     * @notice Get the index of a token by passing in the evm contract address
     * @param evmContract The evm contract address of the token
     * @return index The index of the token
     * @dev Reverts with TokenNotFound if the contract address is not registered
     */
    function getTokenIndex(address evmContract) external view returns (uint32 index) {
        TokenData memory data = addressToIndex[evmContract];

        if (!data.isSet) {
            revert TokenNotFound(evmContract);
        }

        return data.index;
    }

    /**
     * @notice Register a token by passing in its index
     * @param tokenIndex The index of the token to register
     * @dev Calls the token info precompile and stores the mapping
     * @dev For USDC (tokenIndex 0), we manually set the evmContract to USDC_EVM_CONTRACT_ADDRESS
     *      because the tokenInfo.evmContract from the precompile stores the coreDepositWallet address instead
     */
    function setTokenInfo(uint32 tokenIndex) public {
        address evmContract;
        
        // Special handling for USDC (token index 0)
        // For USDC, the tokenInfo.evmContract from the precompile stores the coreDepositWallet address,
        // not the actual USDC EVM contract address. Therefore, we manually set it to the correct address.
        if (tokenIndex == 0) {
            evmContract = USDC_EVM_CONTRACT_ADDRESS;
        } else {
            // call the precompile for other tokens
            evmContract = getTokenAddress(tokenIndex);
        }

        if (evmContract == address(0)) {
            revert NoEvmContract(tokenIndex);
        }

        addressToIndex[evmContract] = TokenData({index: tokenIndex, isSet: true});
    }

    /**
     * @notice Register a batch of tokens by passing in their indices
     * @param startIndex The index of the first token to register
     * @param endIndex The index of the last token to register
     * @dev Enable big blocks before calling this function
     */
    function batchSetTokenInfo(uint32 startIndex, uint32 endIndex) external {
        for (uint32 i = startIndex; i <= endIndex; i++) {
            if (getTokenAddress(i) != address(0)) {
                setTokenInfo(i);
            }
        }
    }

    /**
     * @notice Check if a token is registered in the registry
     * @param evmContract The evm contract address of the token
     * @return bool True if the token is registered, false otherwise
     */
    function hasTokenIndex(address evmContract) external view returns (bool) {
        TokenData memory data = addressToIndex[evmContract];
        return data.isSet;
    }

    /**
     * @notice Get the evm contract address of a token by passing in the index
     * @param index The index of the token
     * @return evmContract The evm contract address of the token
     */
    function getTokenAddress(uint32 index) public view returns (address) {
        (bool success, bytes memory result) = TOKEN_INFO_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        if (!success) revert PrecompileCallFailed();
        TokenInfo memory info = abi.decode(result, (TokenInfo));
        return info.evmContract;
    }

    struct TokenInfo {
        string name;
        uint64[] spots;
        uint64 deployerTradingFeeShare;
        address deployer;
        address evmContract;
        uint8 szDecimals;
        uint8 weiDecimals;
        int8 evmExtraWeiDecimals;
    }

    struct TokenData {
        uint32 index;
        bool isSet; // needed since index is 0 for uninitialized tokens, but is also a valid index
    }

    error TokenNotFound(address evmContract);
    error NoEvmContract(uint32 index);
    error PrecompileCallFailed();
}
