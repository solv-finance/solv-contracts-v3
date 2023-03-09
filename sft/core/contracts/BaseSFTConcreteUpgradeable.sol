// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/access/OwnControl.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/access/SFTConcreteControl.sol";
import "./interface/IBaseSFTConcrete.sol";

abstract contract BaseSFTConcreteUpgradeable is IBaseSFTConcrete, SFTConcreteControl {

	modifier onlyDelegateOwner {
		require(_msgSender() == OwnControl(delegate()).owner(), "only delegate owner");
		_;
	}

	function __BaseSFTConcrete_init() internal onlyInitializing {
		__SFTConcreteControl_init();
	}

	function isSlotValid(uint256 slot_) external view virtual override returns (bool) {
		return _isSlotValid(slot_);
	}

	function _isSlotValid(uint256 slot_) internal view virtual returns (bool);

	uint256[50] private __gap;
}