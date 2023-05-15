// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-abilities/contracts/time-locked-erc20/TimelockedERC20Concrete.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/misc/Constants.sol";
import "./ITimelockedERC20ContainerConcrete.sol";

contract TimelockedERC20ContainerConcrete is ITimelockedERC20ContainerConcrete, TimelockedERC20Concrete {

    address public lockedErc20;

    function initialize(address lockedErc20_) external initializer {
        TimelockedERC20Concrete.__TimelockedERC20Concrete_init();
        TimelockedERC20ContainerConcrete.lockedErc20 = lockedErc20_;
	}

    function _createSlot(address /* txSender_ */, address erc20_, bytes memory inputSlotInfo_) 
        internal virtual override returns (uint256 slot_) 
    {
        require(lockedErc20 == address(0) || erc20_ == lockedErc20, "TLC-Concrete: unsupported erc20");
        InputSlotInfo memory inputSlotInfo = abi.decode(inputSlotInfo_, (InputSlotInfo));

        // issuer must be 0x0 for non-flexible cases, and vice versa
        require(
            (inputSlotInfo.isFlexible && inputSlotInfo.issuer != address(0)) || 
            (!inputSlotInfo.isFlexible && inputSlotInfo.issuer == address(0)), 
            "TLC-Concrete: invalid issuer"
        );
        
        TimelockSlotInfo memory slotInfo = TimelockSlotInfo({
            erc20: erc20_,
            issuer: inputSlotInfo.issuer,
            timelockType: inputSlotInfo.timelockType,
            startTime: inputSlotInfo.isFlexible ? 0 : inputSlotInfo.startTime,
            latestStartTime: inputSlotInfo.startTime,
            terms: inputSlotInfo.terms,
            percentages: inputSlotInfo.percentages,
            totalValue: 0,
            isValid: true
        });
        _validateSlotInfo(slotInfo);

        slot_ = TimelockedERC20Concrete.getSlot( 
            slotInfo.erc20, slotInfo.timelockType, slotInfo.latestStartTime, 
            slotInfo.issuer, slotInfo.terms, slotInfo.percentages
        );

        require(!_slotInfos[slot_].isValid, "TLC-Concrete: slot already exists");
        _slotInfos[slot_] = slotInfo;
    }

    function getSlot(address erc20_, bytes calldata inputSlotInfo_) public view override returns (uint256 slot_) {
        InputSlotInfo memory inputSlotInfo = abi.decode(inputSlotInfo_, (InputSlotInfo));
        slot_ = TimelockedERC20Concrete.getSlot(
            erc20_, inputSlotInfo.timelockType, inputSlotInfo.startTime, 
            inputSlotInfo.issuer, inputSlotInfo.terms, inputSlotInfo.percentages
        );
    }

	uint256[49] private __gap;
}