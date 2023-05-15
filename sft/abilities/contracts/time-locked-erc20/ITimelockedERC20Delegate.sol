// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITimelockedERC20Delegate {
	function mint(address mintTo, address erc20, bytes calldata inputSlotInfo, uint256 value) external payable returns (uint256 slot, uint256 tokenId);
	function claim(uint256 tokenId_, address erc20_, uint256 amount_) external;
}