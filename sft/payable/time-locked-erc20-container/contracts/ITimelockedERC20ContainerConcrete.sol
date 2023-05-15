// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-abilities/contracts/time-locked-erc20/ITimelockedERC20Concrete.sol";

interface ITimelockedERC20ContainerConcrete {

	struct InputSlotInfo {
		ITimelockedERC20Concrete.TimelockType timelockType;
		bool isFlexible;
		uint64 startTime;
		address issuer;
		uint64[] terms;
		uint32[] percentages;
	}
}