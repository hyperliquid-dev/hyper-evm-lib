// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {CoreWriterLib, HLConstants} from "@hyper-evm-lib/src/CoreWriterLib.sol";

contract BridgeToEvmTest {
    using SafeERC20 for IERC20;

    address public immutable owner;

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    constructor() payable {
        owner = msg.sender;
    }

    function bridgeToCore(uint64 token, uint256 evmAmount) external payable onlyOwner {
        CoreWriterLib.bridgeToCore(token, evmAmount);
    }

    function bridgeToEvm(uint64 token, uint256 evmAmount) external onlyOwner {
        CoreWriterLib.bridgeToEvm(token, evmAmount, true);
    }

    function bridgeToEvmCoreAmount(uint64 token, uint64 coreAmount) external onlyOwner {
        CoreWriterLib.bridgeToEvm(token, coreAmount, false);
    }

    function withdrawERC20(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner, amount);
    }

    function withdrawETH() external onlyOwner {
        (bool success,) = owner.call{value: address(this).balance}("");
        require(success, "ETH transfer failed");
    }

    receive() external payable {}
}
