// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IEarnConcrete {
	enum PayableState {
		INVALID,
		ISSUING,
		ACTIVE,
		REPAID
	}

	struct InputSlotInfo {
		address currency;
		uint256 issueQuota;
		uint32 interestRate;
		uint64 valueDate;
		uint64 maturity;
		bool transferable;
		string externalURI;
	}

	struct SlotBaseInfo {
		address issuer;
		address currency;
		uint32 interestRate;
		uint64 valueDate;
		uint64 maturity;
		bool transferable;
		bool isValid;
	}

	struct SlotExtInfo {
		uint256 issueQuota;
		string externalURI;
	}

	function slotBaseInfo(uint256 slot_) external returns (SlotBaseInfo memory);
	function slotExtInfo(uint256 slot_) external returns (SlotExtInfo memory);
	function isSlotTransferable(uint256 slot_) external returns (bool);
	function isCurrencyAllowed(address currency_) external returns (bool);

	function setCurrencyOnlyDelegate(address currency_, bool isAllowed_) external;
}