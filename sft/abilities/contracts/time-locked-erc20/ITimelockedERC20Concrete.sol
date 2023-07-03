// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ITimelockedERC20Concrete {
	enum TimelockType {
		LINEAR,
		ONE_TIME,
		STAGED
	}

	struct TimelockSlotInfo {
		bool isValid;
		uint64 startTime;
		address erc20;
		TimelockType timelockType;
		uint64 latestStartTime;
		address issuer;  // issuer for flexible SFT, should be 0x0 for non-flexible SFT
		uint256 totalValue;
		uint64[] terms;
		uint32[] percentages;
	}

	function createSlotOnlyDelegate(address txSender, address erc20, bytes calldata inputSlotInfo) external returns (uint256 slot);
	function mintOnlyDelegate(address txSender, address mintTo, uint256 slot, uint256 tokenId, uint256 value) external;
	function claimOnlyDelegate(uint256 tokenId, address erc20, uint256 claimValue) external;
	function transferOnlyDelegate(uint256 fromTokenId, uint256 toTokenId, uint256 transferValue) external;
	function setStartTimeOnlyDelegate(uint256 slot, uint64 startTime) external;

	function slotInfo(uint256 slot) external view returns (TimelockSlotInfo memory);
	function erc20(uint256 slot_) external view returns (address);
	function issuer(uint256 slot_) external view returns (address);
	function tokenInitialValue(uint256 tokenId_) external view returns (uint256);
	function claimableValue(uint256 tokenId_) external view returns (uint256);

	function getSlot(address erc20_, bytes calldata inputSlotInfo_) external view returns (uint256);
}