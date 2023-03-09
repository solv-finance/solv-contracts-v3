// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface ISlotLockable {

    event SlotLocked(uint256 slot);

    event SlotUnlocked(uint256 slot);

    function slotLocked(uint256 slot) external view returns (bool);
}
