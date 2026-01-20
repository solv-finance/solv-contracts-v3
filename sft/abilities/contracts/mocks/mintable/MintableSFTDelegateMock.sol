// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTDelegateUpgradeable.sol";
import "../../mintable/SFTMintableDelegate.sol";

contract MintableSFTDelegateMock is
  BaseSFTDelegateUpgradeable,
  SFTMintableDelegate
{
  function initialize(
    string memory name_,
    string memory symbol_,
    uint8 decimals_,
    address concrete_,
    address descriptor_,
    address owner_
  ) external initializer {
    SFTMintableDelegate.__SFTMintableDelegate_init(
      name_,
      symbol_,
      decimals_,
      concrete_,
      descriptor_,
      owner_
    );
  }

  function _afterCreateSlot(
    uint256 slot_,
    bytes memory /** inputSlotInfo_ */
  ) internal virtual override {
    SlotOwnable._setSlotOwner(slot_, _msgSender());
  }

  function contractType()
    external
    view
    virtual
    override
    returns (string memory)
  {}
}