// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTDelegateUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../slot-ownable/SlotOwnable.sol";
import "./ITimelockedERC20Delegate.sol";
import "./ITimelockedERC20Concrete.sol";

abstract contract TimelockedERC20Delegate is ITimelockedERC20Delegate, BaseSFTDelegateUpgradeable, SlotOwnable {

	function __TimelockedERC20Delegate_init(
		string memory name_, string memory symbol_, uint8 decimals_, 
		address concrete_, address metadata_, address owner_
	) internal onlyInitializing {
		__BaseSFTDelegate_init(name_, symbol_, decimals_, concrete_, metadata_, owner_);
	}

	function mint(address mintTo_, address erc20_, bytes calldata inputSlotInfo_, uint256 tokenInAmount_) 
		external payable virtual override nonReentrant returns (uint256 slot_, uint256 tokenId_) 
	{
		slot_ = _createSlotIfNotExist(erc20_, inputSlotInfo_);

		_timelock_doTransferIn(erc20_, _msgSender(), tokenInAmount_);
		uint256 mintValue = tokenInAmount_ * (10 ** valueDecimals()) / (10 ** ERC20(erc20_).decimals());
		_beforeMint(mintTo_, slot_, mintValue);
		tokenId_ = _mint(mintTo_, slot_, mintValue);
		ITimelockedERC20Concrete(concrete()).mintOnlyDelegate(_msgSender(), mintTo_, slot_, tokenId_, mintValue);
		_afterMint(mintTo_, tokenId_, slot_, mintValue);
		emit MintValue(slot_, tokenId_, mintValue);
	}

	function claim(uint256 tokenId_, address erc20_, uint256 claimValue_) external override nonReentrant {
		require(_msgSender() == ERC3525Upgradeable.ownerOf(tokenId_), "not owner");
		ITimelockedERC20Concrete(concrete()).claimOnlyDelegate(tokenId_, erc20_, claimValue_);
		if (_timelock_burn_id() && ERC3525Upgradeable.balanceOf(tokenId_) == claimValue_) {
			ERC3525Upgradeable._burn(tokenId_);
		} else {
			ERC3525Upgradeable._burnValue(tokenId_, claimValue_);
		}

		uint256 tokenOutAmount = claimValue_ * (10 ** ERC20(erc20_).decimals()) / (10 ** valueDecimals());
		_timelock_doTransferOut(erc20_, _msgSender(), tokenOutAmount);
	}

	function setStartTime(uint256 slot_, uint64 startTime_) external virtual onlySlotOwner(slot_) {
		ITimelockedERC20Concrete(concrete()).setStartTimeOnlyDelegate(slot_, startTime_);
	}

	function _createSlotIfNotExist(address erc20_, bytes calldata inputSlotInfo_) internal virtual returns (uint256 slot_) {
		slot_ = ITimelockedERC20Concrete(concrete()).getSlot(erc20_, inputSlotInfo_);
		if (!IBaseSFTConcrete(concrete()).isSlotValid(slot_)) {
			_beforeCreateSlot(erc20_, inputSlotInfo_);
			ITimelockedERC20Concrete(concrete()).createSlotOnlyDelegate(_msgSender(), erc20_, inputSlotInfo_);
			ERC3525SlotEnumerableUpgradeable._createSlot(slot_);
			_afterCreateSlot(slot_);
			emit CreateSlot(slot_, ITimelockedERC20Concrete(concrete()).issuer(slot_), inputSlotInfo_);
		}
	}

	function _beforeCreateSlot(address erc20_, bytes memory inputSlotInfo_) internal virtual {}
	function _afterCreateSlot(uint256 slot_) internal virtual {}

	function _beforeMint(address mintTo_, uint256 slot_, uint256 value_) internal virtual {}
	function _afterMint(address mintTo_, uint256 tokenId_, uint256 slot_, uint256 value_) internal virtual {}

	function _beforeValueTransfer(
        address from_, address to_, uint256 fromTokenId_, uint256 toTokenId_, uint256 slot_, uint256 value_
    ) internal virtual override {
        super._beforeValueTransfer(from_, to_, fromTokenId_, toTokenId_, slot_, value_);
        
		if (fromTokenId_ != 0 && toTokenId_ != 0) { 
            ITimelockedERC20Concrete(concrete()).transferOnlyDelegate(fromTokenId_, toTokenId_, value_);
		}
    }

	function _timelock_doTransferIn(address erc20_, address from_, uint256 amount_) internal virtual;
	function _timelock_doTransferOut(address erc20_, address to_, uint256 amount_) internal virtual;
	function _timelock_burn_id() internal virtual returns (bool) { return true; }

	uint256[50] private __gap;
}