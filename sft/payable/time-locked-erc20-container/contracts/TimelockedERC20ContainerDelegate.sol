// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-abilities/contracts/time-locked-erc20/TimelockedERC20Delegate.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/time-locked-erc20/ITimelockedERC20Concrete.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/helpers/ERC20TransferHelper.sol";

contract TimelockedERC20ContainerDelegate is TimelockedERC20Delegate {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
        _disableInitializers();
    }
    
    function initialize(
        string memory name_, string memory symbol_, uint8 decimals_, address concrete_, address metadata_, address owner_
    ) external initializer {
        TimelockedERC20Delegate.__TimelockedERC20Delegate_init(name_, symbol_, decimals_, concrete_, metadata_, owner_);
	}

    function _afterCreateSlot(uint256 slot_) internal virtual override {
        address issuer = ITimelockedERC20Concrete(concrete()).issuer(slot_);
		SlotOwnable._setSlotOwner(slot_, issuer);
    }

    function _timelock_doTransferIn(address erc20_, address from_, uint256 amount_) internal virtual override {
        ERC20TransferHelper.doTransferIn(erc20_, from_, amount_);
    }

    function _timelock_doTransferOut(address erc20_, address to_, uint256 amount_) internal virtual override {
        ERC20TransferHelper.doTransferOut(erc20_, payable(to_), amount_);
    }

    function contractType() external view virtual override returns (string memory) {
        return "Time-locked ERC20 Container";
    }

	uint256[50] private __gap;
}