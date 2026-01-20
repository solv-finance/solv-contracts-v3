// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-address-resolver/contracts/ResolverCache.sol";
import "../OpenFundMarket.sol";
import "../OFMConstants.sol";
import "./INavOracle.sol";

contract NavOracle is INavOracle, AdminControl, ResolverCache {

	struct PoolNavInfo {
		mapping(uint256 => uint256) navs;
		uint256 latestSetNavTime;
		uint256 allTimeHighRedeemNav;
	}

	mapping(bytes32 => PoolNavInfo) public poolNavInfos;

	mapping(bytes32 => uint256) public specificMaxNavDiffs;

	// The default max nav diff for all pools, applied if specific max nav diff is not set
	uint256 public defaultMaxNavDiff;

	// Set nav times within the current day
	mapping(bytes32 => uint256) public dailySetNavTimes;

	// The daily set nav times limit for each pool
	mapping(bytes32 => uint256) public dailySetNavTimesLimits;

	// The default daily set nav times limit for all pools, applied if specific daily set nav times limit is not set
	uint256 public defaultDailySetNavTimesLimit;

	uint256 public constant NAV_DIFF_BASE = 1e8;

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

	function setDefaultMaxNavDiffOnlyAdmin(uint256 maxNavDiff_) external virtual onlyAdmin {
		defaultMaxNavDiff = maxNavDiff_;
		emit SetDefaultMaxNavDiff(maxNavDiff_);
	}

	function setMaxNavDiffOnlyAdmin(bytes32 poolId_, uint256 maxNavDiff_) external virtual onlyAdmin {
		specificMaxNavDiffs[poolId_] = maxNavDiff_;
		emit SetMaxNavDiff(poolId_, maxNavDiff_);
	}

	function setDefaultDailySetNavTimesLimitOnlyAdmin(uint256 limit_) external virtual onlyAdmin {
		defaultDailySetNavTimesLimit = limit_;
		emit SetDefaultDailySetNavTimesLimit(limit_);
	}

	function setDailySetNavTimesLimitOnlyAdmin(bytes32 poolId_, uint256 limit_) external virtual onlyAdmin {
		dailySetNavTimesLimits[poolId_] = limit_;
		emit SetDailySetNavTimesLimit(poolId_, limit_);
	}

	function setSubscribeNavOnlyAdmin(bytes32 poolId_, uint256 time_, uint256 nav_)
		external virtual onlyAdmin 
	{
		_setSubscribeNav(poolId_, time_, nav_);
	}

	function setSubscribeNavOnlyMarket(bytes32 poolId_, uint256 time_, uint256 nav_) 
		external virtual override onlyMarket 
	{
		uint256 dayTime = time_ / 86400 * 86400;
		uint256 latestNavTime = poolNavInfos[poolId_].latestSetNavTime;

		if (dayTime >= latestNavTime) {
			// The latest nav diff should not exceed the max nav diff
			if (latestNavTime > 0) {
				uint256 latestNav = poolNavInfos[poolId_].navs[latestNavTime];
				uint256 navDiffValue = nav_ > latestNav ? nav_ - latestNav : latestNav - nav_;
				uint256 maxNavDiff = specificMaxNavDiffs[poolId_] > 0 ? specificMaxNavDiffs[poolId_] : defaultMaxNavDiff;
				require(navDiffValue * NAV_DIFF_BASE <= latestNav * maxNavDiff, "NavOracle: nav diff exceeds max diff");
			}

			// daily set nav times control
			if (dayTime == latestNavTime) {
				uint256 dailySetNavTimesLimit = dailySetNavTimesLimits[poolId_] > 0 ? dailySetNavTimesLimits[poolId_] : defaultDailySetNavTimesLimit;
				require(dailySetNavTimes[poolId_] < dailySetNavTimesLimit, "NavOracle: daily set nav times limit reached");
				dailySetNavTimes[poolId_] += 1;
			} else {
				dailySetNavTimes[poolId_] = 1;
			}
		}
	
		_setSubscribeNav(poolId_, time_, nav_);
	}

	function _setSubscribeNav(bytes32 poolId_, uint256 time_, uint256 nav_) internal virtual {
		require(time_ <= block.timestamp, "NavOracle: invalid time");
		uint256 dayTime = time_ / 86400 * 86400;
		poolNavInfos[poolId_].navs[dayTime] = nav_;
		if (dayTime > poolNavInfos[poolId_].latestSetNavTime) {
			poolNavInfos[poolId_].latestSetNavTime = dayTime;
		}
		emit SetSubscribeNav(poolId_, dayTime, nav_);
	}

	function updateAllTimeHighRedeemNavOnlyMarket(bytes32 poolId_, uint256 nav_) 
		external virtual override onlyMarket
	{
		uint256 previousNav = poolNavInfos[poolId_].allTimeHighRedeemNav;
		if (nav_ > previousNav) {
			poolNavInfos[poolId_].allTimeHighRedeemNav = nav_;
			emit UpdateAllTimeHighRedeemNav(poolId_, previousNav, nav_);
		}
	}

	function getSubscribeNav(bytes32 poolId_, uint256 time_) 
		external view virtual override returns (uint256 nav_, uint256 navTime_) 
	{
		PoolNavInfo storage poolNavInfo = poolNavInfos[poolId_];
		navTime_ = time_ / 86400 * 86400;
		nav_ = poolNavInfo.navs[navTime_];

		// if nav of the day is not set, return the latest nav info
		if (nav_ == 0) {
			navTime_ = poolNavInfo.latestSetNavTime;
			nav_ = poolNavInfo.navs[navTime_];
		}
	}

	function getAllTimeHighRedeemNav(bytes32 poolId_) 
		external view virtual override returns (uint256) 
	{
		return poolNavInfos[poolId_].allTimeHighRedeemNav;
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