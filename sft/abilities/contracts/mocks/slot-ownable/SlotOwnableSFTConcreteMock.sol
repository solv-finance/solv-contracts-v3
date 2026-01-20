// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTConcreteUpgradeable.sol";
import "../../slot-ownable/SlotOwnable.sol";

contract SlotOwnableSFTConcreteMock is BaseSFTConcreteUpgradeable {
    function initialize() external initializer {
        BaseSFTConcreteUpgradeable.__BaseSFTConcrete_init();
    }

    function _isSlotValid(uint256 /** slot_ */) internal view virtual override returns (bool) {
        return true;
    }
}