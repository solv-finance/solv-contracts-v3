// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-abilities/contracts/time-locked-erc20/TimelockedERC20Delegate.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/time-locked-erc20/ITimelockedERC20Concrete.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/helpers/ERC20TransferHelper.sol";

contract TimelockedERC20ContainerDelegate is TimelockedERC20Delegate {

    function initialize(
        string memory name_, string memory symbol_, uint8 decimals_, address concrete_, address metadata_, address owner_
    ) external initializer {
        TimelockedERC20Delegate.__TimelockedERC20Delegate_init(name_, symbol_, decimals_, concrete_, metadata_, owner_);
	}

    function _afterCreateSlot(uint256 slot_) internal virtual override {
        address issuer = ITimelockedERC20Concrete(concrete()).issuer(slot_);
		SlotOwnable._setSlotOwner(slot_, issuer);
    }

    function _afterMint(address /* mintTo_ */, uint256 slot_, uint256 /* tokenId_ */, uint256 value_) internal virtual override {
    	address erc20 = ITimelockedERC20Concrete(concrete()).erc20(slot_);
        ERC20TransferHelper.doTransferIn(erc20, _msgSender(), value_);
    }

    function _timelock_doTransferIn(address erc20_, address from_, uint256 amount_) internal virtual override {
        ERC20TransferHelper.doTransferIn(erc20_, from_, amount_);
    }

    function _timelock_doTransferOut(address erc20_, address to_, uint256 amount_) internal virtual override {
        ERC20TransferHelper.doTransferOut(erc20_, payable(to_), amount_);
    }

	uint256[50] private __gap;
}