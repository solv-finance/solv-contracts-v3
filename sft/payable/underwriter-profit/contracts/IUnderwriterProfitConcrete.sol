// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-abilities/contracts/mintable/ISFTMintableConcrete.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/multi-rechargeable/IMultiRechargeableConcrete.sol";

interface IUnderwriterProfitConcrete is ISFTMintableConcrete, IMultiRechargeableConcrete {
	struct InputSlotInfo {
		string name;
		address currency;
	}

	struct UnderwriterProfitSlotInfo {
		string name;
		address currency;
		bool isValid;
	}

	function getSlot(string memory name_, address currency_) external view returns (uint256);
	function slotBaseInfo(uint256 slot_) external view returns(UnderwriterProfitSlotInfo memory);
}