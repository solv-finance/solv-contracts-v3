// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-solidity-utils/contracts/access/OwnControl.sol";

abstract contract SlotOwnable is OwnControl {
	event NewSlotOwner(address oldSlotOwner, address newSlotOwner);

	// slot => slot owner
	mapping(uint256 => address) private _slotOwners;

	modifier onlySlotOwner(uint256 slot) {
		require(slotOwner(slot) == _msgSender(), "only slot owner");
		_;
	}

	function __SlotOwnable_init(address owner_) internal onlyInitializing {
		OwnControl.__OwnControl_init(owner_);
	}

	function slotOwner(uint256 slot_) public view virtual returns (address) {
		return _slotOwners[slot_];
	}

	function setSlotOwner(uint256 slot_, address newSlotOwner_) external virtual onlyOwner {
		_setSlotOwner(slot_, newSlotOwner_);
	}

	function _setSlotOwner(uint256 slot_, address newSlotOwner_) internal virtual {
		emit NewSlotOwner(_slotOwners[slot_], newSlotOwner_);
		_slotOwners[slot_] = newSlotOwner_;
	}

	uint256[49] private __gap;
}