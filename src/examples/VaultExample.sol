// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {CoreWriterLib, HLConversions} from "@hyper-evm-lib/src/CoreWriterLib.sol";
import {PrecompileLib} from "@hyper-evm-lib/src/PrecompileLib.sol";

/**
 * @title VaultExample
 * @dev This contract demonstrates CoreWriterLib vault functionality.
 */
contract VaultExample {
    using CoreWriterLib for *;

    uint64 public constant USDC_TOKEN_ID = 0;

    /*//////////////////////////////////////////////////////////////
                        Basic Vault Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits USDC to a specified vault
     * @param vault Address of the vault to deposit to
     * @param usdcAmount Amount of USDC to deposit
     */
    function depositToVault(address vault, uint64 usdcAmount) external {
        CoreWriterLib.vaultTransfer(vault, true, usdcAmount);
    }

    /**
     * @notice Withdraws USDC from a specified vault
     * @param vault Address of the vault to withdraw from
     * @param usdcAmount Amount of USDC to withdraw
     */
    function withdrawFromVault(address vault, uint64 usdcAmount) external {
        CoreWriterLib.vaultTransfer(vault, false, usdcAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        Advanced Vault Operations
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Withdraws USDC from vault and sends to recipient
     * @dev vaultTransfer checks if funds are withdrawable and reverts if locked
     * @param vault Address of the vault to withdraw from
     * @param recipient Address to send the withdrawn USDC to
     * @param coreAmount Amount of USDC to withdraw and send
     */
    function withdrawFromVaultAndSend(address vault, address recipient, uint64 coreAmount) external {
        uint64 usdcPerpAmount = HLConversions.weiToPerp(coreAmount);

        CoreWriterLib.vaultTransfer(vault, false, usdcPerpAmount);

        CoreWriterLib.transferUsdClass(usdcPerpAmount, false);

        CoreWriterLib.spotSend(recipient, USDC_TOKEN_ID, coreAmount);
    }

    /**
     * @notice Transfers USDC from spot to perp and deposits to vault
     * @param vault Address of the vault to deposit USDC to
     * @param coreAmount Amount of USDC to transfer and deposit to vault
     */
    function transferUsdcToPerpAndDepositToVault(address vault, uint64 coreAmount) external {
        uint64 usdcPerpAmount = HLConversions.weiToPerp(coreAmount);

        CoreWriterLib.transferUsdClass(usdcPerpAmount, true);

        CoreWriterLib.vaultTransfer(vault, true, usdcPerpAmount);
    }

    /*//////////////////////////////////////////////////////////////
                        Vault Information
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Gets the vault equity for a user in a specific vault
     * @param user Address of the user to check
     * @param vault Address of the vault to check
     * @return equity Amount of equity the user has in the vault
     * @return lockedUntilTimestamp Timestamp until which the equity is locked
     */
    function getVaultEquity(address user, address vault)
        public
        view
        returns (uint64 equity, uint64 lockedUntilTimestamp)
    {
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(user, vault);
        return (vaultEquity.equity, vaultEquity.lockedUntilTimestamp);
    }

    /**
     * @notice Checks if funds are withdrawable from a vault for a user
     * @param user Address of the user to check
     * @param vault Address of the vault to check
     * @return withdrawable True if funds can be withdrawn, false if locked
     */
    function isWithdrawable(address user, address vault) public view returns (bool withdrawable) {
        PrecompileLib.UserVaultEquity memory vaultEquity = PrecompileLib.userVaultEquity(user, vault);
        return CoreWriterLib.toMilliseconds(uint64(block.timestamp)) >= vaultEquity.lockedUntilTimestamp;
    }

    receive() external payable {}
}
