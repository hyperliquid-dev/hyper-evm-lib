// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface ICoreDepositWallet {
    function deposit(uint256 amount, uint32 destinationDex) external;
    function depositFor(address recipient, uint256 amount, uint32 destinationDex) external;
}

