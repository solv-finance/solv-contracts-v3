// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@solvprotocol/contracts-v3-address-resolver/contracts/ResolverCache.sol";
import "@solvprotocol/contracts-v3-sft-open-fund/contracts/open-fund-redemptions/OpenFundRedemptionDelegate.sol";
import "@solvprotocol/contracts-v3-sft-open-fund/contracts/open-fund-redemptions/OpenFundRedemptionConcrete.sol";
import "../OpenFundMarketStorage.sol";
import "../OpenFundMarket.sol";
import "../OFMConstants.sol";
import "./INavOracle.sol";

interface IERC721Enumerable {
	function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256);
}

contract FoFNavOracle is INavOracle, AdminControl, ResolverCache {
	using EnumerableSet for EnumerableSet.Bytes32Set;

	event AddFoFPool(bytes32 indexed fofPoolId);
	event AddFeederPool(bytes32 indexed fofPoolId, bytes32 indexed feederPoolId);
	event removeFoFPool(bytes32 indexed fofPoolId);
	event removeFeederPool(bytes32 indexed fofPoolId, bytes32 indexed feederPoolId);
	event UpdateSubscribeNav(bytes32 indexed fofPoolId, uint256 nav);

	mapping(bytes32 => EnumerableSet.Bytes32Set) internal _feederPoolIds;
	mapping(bytes32 => uint256) public allTimeHighRedeemNav;

	mapping(bytes32 => uint256) public subscribeNaves;

	modifier onlyMarket {
		require(msg.sender == _openFundMarket());
		_;
	}

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
        _disableInitializers();
    }
    
	function initialize(address resolver_) external initializer {
		__AdminControl_init_unchained(_msgSender());
		__ResolverCache_init(resolver_);
	}

	function setSubscribeNavOnlyMarket(bytes32 /*fofPoolId_*/, uint256 /*time_*/, uint256 /*nav_*/) external onlyMarket {
		//do nothing
	}

	function setSubscribeNavOnlyAdmin(bytes32 fofPoolId_, uint256 nav_) external onlyAdmin {
		subscribeNaves[fofPoolId_] = nav_;
		emit UpdateSubscribeNav(fofPoolId_, nav_);
	}

	function updateAllTimeHighRedeemNavOnlyMarket(bytes32 fofPoolId_, uint256 nav_)  external {
		uint256 previousNav = allTimeHighRedeemNav[fofPoolId_];
		if (nav_ > previousNav) {
			allTimeHighRedeemNav[fofPoolId_] = nav_;
			emit UpdateAllTimeHighRedeemNav(fofPoolId_, previousNav, nav_);
		}
	}

	function getSubscribeNav(bytes32 fofPoolId_, uint256 /** time_ */) external view returns (uint256 nav_, uint256 navTime_) {
		OpenFundMarket.PoolInfo memory poolInfo = _getPoolInfo(fofPoolId_);
		nav_ = subscribeNaves[fofPoolId_];
		if (nav_ == 0) {
			nav_ = 10 ** ERC20(poolInfo.currency).decimals();
		}
		navTime_ = block.timestamp;
	}

	function getFoFTotalShares(bytes32 fofPoolId_) external view returns (uint256 totalValue_) { 
		OpenFundMarket.PoolInfo memory poolInfo = _getPoolInfo(fofPoolId_);	
		totalValue_ = _getFoFTotalShares(poolInfo);
	}

	function _getFoFTotalShares(OpenFundMarket.PoolInfo memory poolInfo) internal view returns (uint256 totalValue_) {
		//shares total value
		address shareConcrete = ISFTDelegateControl(poolInfo.poolSFTInfo.openFundShare).concrete();
		totalValue_ = IMultiRepayableConcrete(shareConcrete).slotTotalValue(poolInfo.poolSFTInfo.openFundShareSlot);
	}

	function getAllTimeHighRedeemNav(bytes32 fofPoolId_) external view returns (uint256) {
		return allTimeHighRedeemNav[fofPoolId_];
	}

	function getFeederPoolIds(bytes32 fofPoolId_) external view returns (bytes32[] memory) {
		return _feederPoolIds[fofPoolId_].values();
	}

	function addPool(bytes32 fofPoolId_, bytes32[] calldata feederPoolIds_) external onlyAdmin {
		OpenFundMarket.PoolInfo memory fofPoolInfo = _getPoolInfo(fofPoolId_);
		if (_feederPoolIds[fofPoolId_].length() == 0) {
			emit AddFoFPool(fofPoolId_);
		}

		for (uint256 i = 0; i < feederPoolIds_.length; i++) {
			OpenFundMarket.PoolInfo memory feederPoolInfo = _getPoolInfo(feederPoolIds_[i]);
			require(fofPoolInfo.currency == feederPoolInfo.currency, "FoFNavOracle: currency mismatch");
			if (_feederPoolIds[fofPoolId_].add(feederPoolIds_[i])) {
				emit AddFeederPool(fofPoolId_, feederPoolIds_[i]);
			}
		}
	}

	function removePool(bytes32 fofPoolId_, bytes32[] calldata feederPoolIds_) external onlyAdmin {
		for (uint256 i = 0; i < feederPoolIds_.length; i++) {
			if (_feederPoolIds[fofPoolId_].remove(feederPoolIds_[i])) {
				emit removeFeederPool(fofPoolId_, feederPoolIds_[i]);
			}
		}
		if (_feederPoolIds[fofPoolId_].length() == 0) {
			emit removeFoFPool(fofPoolId_);
		}
	}

	function getFoFPoolValue(bytes32 fofPoolId_) external view returns (uint256 feederFundPoolValue_) {
		OpenFundMarket.PoolInfo memory poolInfo = _getPoolInfo(fofPoolId_);
		feederFundPoolValue_ = _getFoFPoolValue(fofPoolId_, poolInfo);
	}

	function _getFoFPoolValue(bytes32 fofPoolId_, OpenFundMarket.PoolInfo memory poolInfo) internal view returns (uint256 fofPoolValue_) {
		//vault currency
		uint256 vaultCurrency = IERC20(poolInfo.currency).balanceOf(poolInfo.vault);
		fofPoolValue_ += vaultCurrency;

		//feeder fund pool value
		for (uint256 i = 0; i < _feederPoolIds[fofPoolId_].length(); i++) {
			fofPoolValue_ += _getFeederFundPoolValue(poolInfo.vault, _feederPoolIds[fofPoolId_].at(i));
		}

		uint256 previousRedeemSlot = OpenFundMarket(_openFundMarket()).previousRedeemSlot(fofPoolId_);
		OpenFundRedemptionConcrete redemptionConcrete = OpenFundRedemptionConcrete(OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).concrete());
		uint256 previousRedeemNav = OpenFundRedemptionConcrete(redemptionConcrete).getRedeemNav(previousRedeemSlot);
		if (previousRedeemNav > 0) {
			uint256 previousSlotTotalValue = redemptionConcrete.slotTotalValue(previousRedeemSlot);
            uint256 previousSlotCurrencyBalance = redemptionConcrete.slotCurrencyBalance(previousRedeemSlot);
            uint8 redemptionValueDecimals = OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).valueDecimals();
			uint256 previousSlotTotalPayAmount = previousSlotTotalValue * previousRedeemNav / (10 ** redemptionValueDecimals);
			uint256 previousSlotUnpaidValue = previousSlotCurrencyBalance > previousSlotTotalPayAmount ? 0 : previousSlotTotalPayAmount - previousSlotCurrencyBalance;
			fofPoolValue_ -= previousSlotUnpaidValue;
		}
	}

	function getFeederFundPoolValue(bytes32 fofPoolId_, bytes32 feederPoolId_) external view returns (uint256 value_) {
		OpenFundMarket.PoolInfo memory poolInfo = _getPoolInfo(fofPoolId_);
		value_ = _getFeederFundPoolValue(poolInfo.vault, feederPoolId_);
	}

	function _getFeederFundPoolValue(address fofVault_, bytes32 feederPoolId_) internal view returns (uint256 balance_) {
		OpenFundMarket.PoolInfo memory poolInfo = _getPoolInfo(feederPoolId_);
		//holding shares
		uint256 shares = _getSFTBalance(fofVault_, poolInfo.poolSFTInfo.openFundShare, poolInfo.poolSFTInfo.openFundShareSlot);
		(uint256 subscribeNav, ) = INavOracle(poolInfo.navOracle).getSubscribeNav(feederPoolId_, block.timestamp);
		uint256 sharesValue = subscribeNav * shares;
		balance_ += sharesValue;

		//redeeming
		uint256 redemptions = _getSFTBalance(fofVault_, poolInfo.poolSFTInfo.openFundRedemption, poolInfo.poolSFTInfo.latestRedeemSlot);
		if (redemptions > 0) {
			address redemptionConcrete = OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).concrete();
			uint256 redeemNav = OpenFundRedemptionConcrete(redemptionConcrete).getRedeemNav(poolInfo.poolSFTInfo.latestRedeemSlot);
			uint256 redemptionsValue = (redeemNav > 0 ? redeemNav : subscribeNav) * redemptions;
			balance_ += redemptionsValue;
		}

		//redeemed
		uint256 redeemedSlot = OpenFundMarket(_openFundMarket()).previousRedeemSlot(feederPoolId_);
		uint256 redeemed = _getSFTBalance(fofVault_, poolInfo.poolSFTInfo.openFundRedemption, redeemedSlot);
		if (redeemed > 0) {
			address redemptionConcrete = OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).concrete();
			uint256 redeemNav = OpenFundRedemptionConcrete(redemptionConcrete).getRedeemNav(redeemedSlot);
			uint256 redeemedValue = (redeemNav > 0 ? redeemNav : subscribeNav) * redeemed;
			balance_ += redeemedValue;
		}

		balance_ /= (10 ** OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).valueDecimals());
	}

	function _getSFTBalance(address fofVault_, address sft_, uint256 slot_) internal view returns (uint256 balance_) {
		IERC3525 sft = IERC3525(sft_);
		uint256 numberOfSFT = IERC721(sft_).balanceOf(fofVault_);
		for (uint256 i = 0; i < numberOfSFT; i++) {
			uint256 tokenId = IERC721Enumerable(sft_).tokenOfOwnerByIndex(fofVault_, i);
			if (sft.slotOf(tokenId) == slot_) {
				balance_ += sft.balanceOf(tokenId);
			}
		}
	}

	function _getPoolInfo(bytes32 poolId_) internal view returns (OpenFundMarket.PoolInfo memory) {
		OpenFundMarket ofm = OpenFundMarket(_openFundMarket());
		(bool success, bytes memory data) = address(ofm).staticcall(abi.encodeWithSignature("poolInfos(bytes32)", poolId_));
		require(success, "FoFNavOracle: poolInfo failed");
		OpenFundMarket.PoolInfo memory poolInfo = abi.decode(data, (IOpenFundMarketStorage.PoolInfo));
		return poolInfo;
	}

	function _openFundMarket() internal view returns (address) {
		return getRequiredAddress(OFMConstants.CONTRACT_OFM, "NavOracle: OFM not set");
	}

	function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory) {
		bytes32[] memory existAddresses = super._resolverAddressesRequired();
		bytes32[] memory newAddresses = new bytes32[](1);
		newAddresses[0] = OFMConstants.CONTRACT_OFM;
		return _combineArrays(existAddresses, newAddresses);
	}	
}