// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTDelegateUpgradeable.sol";
import "../slot-ownable/SlotOwnable.sol";
import "./ISFTMintableDelegate.sol";
import "./ISFTMintableConcrete.sol";

abstract contract SFTMintableDelegate is ISFTMintableDelegate, BaseSFTDelegateUpgradeable, SlotOwnable {

	event SetSlotMintingPaused(uint256 _slot, bool _paused);

	mapping(uint256 => bool) public isSlotMintingPaused;

	function __SFTMintableDelegate_init(string memory name_, string memory symbol_, uint8 decimals_, 
		address concrete_, address metadata_, address owner_) internal onlyInitializing {
		__BaseSFTDelegate_init(name_, symbol_, decimals_, concrete_, metadata_, owner_);
	}

	function createSlot(bytes calldata inputSlotInfo_) external virtual override nonReentrant returns (uint256 slot_) {
		_beforeCreateSlot(inputSlotInfo_);
		slot_ = ISFTMintableConcrete(concrete()).createSlotOnlyDelegate(_msgSender(), inputSlotInfo_);
		ERC3525SlotEnumerableUpgradeable._createSlot(slot_);
		_afterCreateSlot(slot_, inputSlotInfo_);
		emit CreateSlot(slot_, _msgSender(), inputSlotInfo_);
	}

	function mint(address mintTo_, uint256 slot_, uint256 value_) external payable virtual override nonReentrant returns (uint256 tokenId_) {
		require(!isSlotMintingPaused[slot_], "minting is paused");

		_beforeMint(mintTo_, slot_, value_);
		tokenId_ = _mint(mintTo_, slot_, value_);
		ISFTMintableConcrete(concrete()).mintOnlyDelegate(_msgSender(), mintTo_, slot_, tokenId_, value_);
		_afterMint(mintTo_, slot_, tokenId_, value_);
		emit MintValue(tokenId_, slot_, value_);
	}

	function setSlotMintingPaused(uint256 slot_, bool paused_) external virtual {
		require(_msgSender() == owner || _msgSender() == slotOwner(slot_), "only owner or slot owner");
		isSlotMintingPaused[slot_] = paused_;
		emit SetSlotMintingPaused(slot_, paused_);
	}

	function _SFTMintableDelegate_mintValue(uint256 tokenId_, uint256 value_) internal virtual  {
		address tokenOwner = ERC3525Upgradeable.ownerOf(tokenId_);
		uint256 tokenSlot = ERC3525Upgradeable.slotOf(tokenId_);
		require(!isSlotMintingPaused[tokenSlot], "minting is paused");
		
		ERC3525Upgradeable._mintValue(tokenId_, value_);
		ISFTMintableConcrete(concrete()).mintOnlyDelegate(_msgSender(), tokenOwner, tokenSlot, tokenId_, value_);	
	}

	function _beforeCreateSlot(bytes memory inputSlotInfo_) internal virtual {}
	function _afterCreateSlot(uint256 slot_, bytes memory inputSlotInfo_) internal virtual {}
	function _beforeMint(address mintTo_, uint256 slot_, uint256 value_) internal virtual {}
	function _afterMint(address mintTo_, uint256 slot_, uint256 tokenId_, uint256 value_) internal virtual {}

	uint256[49] private __gap;
}