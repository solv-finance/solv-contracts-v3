// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTConcreteUpgradeable.sol";
import "../../mintable/SFTMintableConcrete.sol";

contract MintableSFTConcreteMock is BaseSFTConcreteUpgradeable, SFTMintableConcrete {

    struct InputSlotInfo {
        uint64 createTime;
        uint64 expireTime;
    }

    struct SlotInfo {
        address issuer;
        uint64 createTime;
        uint64 expireTime;
        bool isValid;
    }

    mapping(uint256 => SlotInfo) internal _slotInfos;

    function initialize() external initializer {
        SFTMintableConcrete.__SFTMintableConcrete_init();
    }

    function getSlot(address issuer_, uint64 createTime_, uint64 expireTime_) public pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(issuer_, createTime_, expireTime_)));
    }

    function getSlotInfos(uint256 slot_) public view returns (SlotInfo memory) {
        return _slotInfos[slot_];
    }

    function _isSlotValid(uint256 slot_) internal view virtual override returns (bool) {
        return _slotInfos[slot_].isValid;
    }

    function _createSlot(address txSender_, bytes memory inputSlotInfo_) internal virtual override returns (uint256 slot_) {
        InputSlotInfo memory input = abi.decode(inputSlotInfo_, (InputSlotInfo));

        slot_ = getSlot(txSender_, input.createTime, input.expireTime);
        require(!_slotInfos[slot_].isValid, "MintableSFTConcreteMock: slot already exists");

        _slotInfos[slot_] = SlotInfo({
            issuer: txSender_,
            createTime: input.createTime,
            expireTime: input.expireTime,
            isValid: true
        });
    }

    function _mint(address /** txSender_ */, address /** mintTo_ */, uint256 slot_, uint256 /** tokenId_ */, uint256 /** value_ */) internal virtual override {
        require(_slotInfos[slot_].isValid, "MintableSFTConcreteMock: invalid slot");
    }
}