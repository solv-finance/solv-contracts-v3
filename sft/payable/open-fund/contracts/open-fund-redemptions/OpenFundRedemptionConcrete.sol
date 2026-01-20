// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-abilities/contracts/value-issuable/SFTValueIssuableConcrete.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/fcfs-multi-repayable/FCFSMultiRepayableConcrete.sol";
import "./IOpenFundRedemptionConcrete.sol";

contract OpenFundRedemptionConcrete is IOpenFundRedemptionConcrete, SFTValueIssuableConcrete, FCFSMultiRepayableConcrete {

    event SetRedemptionFeeReceiver(address indexed redemptionFeeReceiver);
    event SetRedemtpionFeeRate(bytes32 indexed poolId, uint256 redemptionFeeRate);

    mapping(uint256 => RedeemInfo) internal _redeemInfos;

    address public redemptionFeeReceiver;

    // poolId => redemptionFeeRate
    mapping(bytes32 => uint256) public redemptionFeeRates;  // base: 1e18

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
        _disableInitializers();
    }
    
    function initialize() external initializer {
        __SFTIssuableConcrete_init();
	}

    function setRedeemNavOnlyDelegate(uint256 slot_, uint256 nav_) external virtual override onlyDelegate {
        _redeemInfos[slot_].nav = nav_;
    }

    function setRedemptionFeeReceiverOnlyAdmin(address redemptionFeeReceiver_) external virtual onlyAdmin {
        redemptionFeeReceiver = redemptionFeeReceiver_;
        emit SetRedemptionFeeReceiver(redemptionFeeReceiver_);
    }

    function setRedemptionFeeRateOnlyAdmin(bytes32 poolId_, uint256 redemptionFeeRate_) external virtual onlyAdmin {
        redemptionFeeRates[poolId_] = redemptionFeeRate_;
        emit SetRedemtpionFeeRate(poolId_, redemptionFeeRate_);
    }

    function getRedemptionFeeRate(uint256 slot_) external view virtual returns (uint256) {
        return redemptionFeeRates[_redeemInfos[slot_].poolId];
    }

    function getRedeemInfo(uint256 slot_) external view virtual override returns (RedeemInfo memory) {
        return _redeemInfos[slot_];
    }

	function getRedeemNav(uint256 slot_) external view virtual override returns (uint256) {
        return _redeemInfos[slot_].nav;
    }
	
    function _isSlotValid( uint256 slot_) internal view virtual override returns (bool) {
        return _redeemInfos[slot_].createTime != 0;
    }

    function _createSlot( address /* txSender_ */, bytes memory inputSlotInfo_) internal virtual override returns (uint256 slot_) {
        RedeemInfo memory redeemInfo = abi.decode(inputSlotInfo_, (RedeemInfo));
        require(redeemInfo.poolId != bytes32(0), "OFRC: invalid poolId");
        require(redeemInfo.currency != address(0), "OFRC: invalid currency");
        require(redeemInfo.createTime != 0, "OFRC: invalid createTime");
        slot_ = _getSlot(redeemInfo.poolId, redeemInfo.currency, redeemInfo.createTime);

        // if the slot is already created, do nothing
        if (_redeemInfos[slot_].createTime == 0) {
            _redeemInfos[slot_] = redeemInfo;
        }
    }

    function _getSlot(bytes32 poolId_, address currency_, uint256 createTime_) internal view virtual returns (uint256) {
		uint256 chainId;
        assembly { chainId := chainid() }
		return uint256(keccak256(abi.encodePacked(chainId, delegate(), poolId_, currency_, createTime_)));
    }

    function _mint(
        address /** txSender_ */, address currency_, address /** mintTo_ */, 
        uint256 slot_, uint256 /** tokenId_ */, uint256 /** amount_ */
    ) internal virtual override {
        require(_isSlotValid(slot_), "OFRC: invalid slot");
        require(_redeemInfos[slot_].currency == currency_, "OFRC: invalid currency");
    }

    function _burn(uint256 tokenId_, uint256 burnValue_) internal virtual override {
        uint256 slot = ERC3525Upgradeable(delegate()).slotOf(tokenId_);
        FCFSMultiRepayableConcrete._slotValueInfo[slot].slotTotalValue -= burnValue_;
    }

    function _currency( uint256 slot_) internal view virtual override returns (address) {
        return _redeemInfos[slot_].currency;
    }

    function _repayRate( uint256 slot_) internal view virtual override returns (uint256) {
        return _redeemInfos[slot_].nav;
    }
	

}