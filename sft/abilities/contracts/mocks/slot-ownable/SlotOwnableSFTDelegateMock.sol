// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTDelegateUpgradeable.sol";
import "../../slot-ownable/SlotOwnable.sol";

contract SlotOwnableSFTDelegateMock is BaseSFTDelegateUpgradeable, SlotOwnable {
  function initialize(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    address concrete_,
    address descriptor_,
    address owner_
  ) external initializer {
    BaseSFTDelegateUpgradeable.__BaseSFTDelegate_init(
      name_,
      symbol_,
      decimals_,
      concrete_,
      descriptor_,
      owner_
    );
    SlotOwnable.__SlotOwnable_init(owner_);
  }

  function createSlot(uint256 slot_) external virtual {
    ERC3525SlotEnumerableUpgradeable._createSlot(slot_);
    _setSlotOwner(slot_, _msgSender());
  }

  function testOnlySlotOwner(
    uint256 slot_
  ) external virtual onlySlotOwner(slot_) {}

  function contractType()
    external
    view
    virtual
    override
    returns (string memory)
  {}
}