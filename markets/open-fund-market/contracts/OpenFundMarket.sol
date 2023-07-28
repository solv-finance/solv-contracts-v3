// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@solvprotocol/contracts-v3-address-resolver/contracts/ResolverCache.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/value-issuable/ISFTValueIssuableDelegate.sol";
import "@solvprotocol/erc-3525/IERC3525.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/helpers/ERC20TransferHelper.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/helpers/ERC3525TransferHelper.sol";
import "@solvprotocol/contracts-v3-sft-open-fund/contracts/open-fund-shares/OpenFundShareConcrete.sol";
import "@solvprotocol/contracts-v3-sft-open-fund/contracts/open-fund-shares/OpenFundShareDelegate.sol";
import "@solvprotocol/contracts-v3-sft-open-fund/contracts/open-fund-redemptions/IOpenFundRedemptionConcrete.sol";
import "@solvprotocol/contracts-v3-sft-open-fund/contracts/open-fund-redemptions/OpenFundRedemptionConcrete.sol";
import "@solvprotocol/contracts-v3-sft-open-fund/contracts/open-fund-redemptions/OpenFundRedemptionDelegate.sol";
import "@solvprotocol/contracts-v3-sft-earn/contracts/IEarnConcrete.sol";
import "./IOpenFundMarket.sol";
import "./OpenFundMarketStorage.sol";
import "./OFMConstants.sol";
import "./whitelist/IOFMWhitelistStrategyManager.sol";
import "./oracle/INavOracle.sol";

contract OpenFundMarket is IOpenFundMarket, OpenFundMarketStorage, ReentrancyGuardUpgradeable, ResolverCache {
    	using EnumerableSet for EnumerableSet.UintSet;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
        _disableInitializers();
    }
    
    function initialize(address resolver_, address owner_) external initializer {
		__OwnControl_init(owner_);
		__ReentrancyGuard_init();
		__ResolverCache_init(resolver_);
	}

    function createPool(InputPoolInfo calldata inputPoolInfo_) external virtual override nonReentrant returns (bytes32 poolId_) {
        _validateInputPoolInfo(inputPoolInfo_);

        IEarnConcrete.InputSlotInfo memory openFundInputSlotInfo = IEarnConcrete.InputSlotInfo({
            currency: inputPoolInfo_.currency,
            supervisor: inputPoolInfo_.redeemNavManager,
            issueQuota: type(uint256).max,
            interestType: IEarnConcrete.InterestType.FLOATING,
            interestRate: 0,
            valueDate: inputPoolInfo_.valueDate,
            maturity: inputPoolInfo_.subscribeLimitInfo.fundraisingEndTime,
            createTime: inputPoolInfo_.createTime,
            transferable: true,
            externalURI: ""
        });

        uint256 slot = ISFTValueIssuableDelegate(inputPoolInfo_.openFundShare).createSlotOnlyIssueMarket(_msgSender(), abi.encode(openFundInputSlotInfo));
        poolId_ = keccak256(abi.encode(inputPoolInfo_.openFundShare, slot));

        require(poolInfos[poolId_].poolSFTInfo.openFundShareSlot == 0, "OFM: pool already exists");

        PoolInfo memory poolInfo = PoolInfo({
            poolSFTInfo: PoolSFTInfo({
                openFundShare: inputPoolInfo_.openFundShare,
                openFundShareSlot: slot,
                openFundRedemption: inputPoolInfo_.openFundRedemption,
                latestRedeemSlot: 0
            }),
            poolFeeInfo: PoolFeeInfo({
                carryRate: inputPoolInfo_.carryRate,
                carryCollector: inputPoolInfo_.carryCollector,
                latestProtocolFeeSettleTime: inputPoolInfo_.valueDate
            }),
            managerInfo: ManagerInfo ({
                poolManager: _msgSender(),
                subscribeNavManager: inputPoolInfo_.subscribeNavManager,
                redeemNavManager: inputPoolInfo_.redeemNavManager
            }),
            subscribeLimitInfo: inputPoolInfo_.subscribeLimitInfo,
            vault: inputPoolInfo_.vault,
            currency: inputPoolInfo_.currency,
            navOracle: inputPoolInfo_.navOracle,
            valueDate: inputPoolInfo_.valueDate,
            permissionless: inputPoolInfo_.whiteList.length == 0,
            fundraisingAmount: 0
        });

        poolInfos[poolId_] = poolInfo;

        uint256 initialNav = 10 ** ERC20(inputPoolInfo_.currency).decimals();
        INavOracle(inputPoolInfo_.navOracle).setSubscribeNavOnlyMarket(poolId_, block.timestamp, initialNav);
        INavOracle(inputPoolInfo_.navOracle).updateAllTimeHighRedeemNavOnlyMarket(poolId_, initialNav);

        _whitelistStrategyManager().setWhitelist(poolId_, inputPoolInfo_.whiteList);

        emit CreatePool(poolId_, poolInfo.currency, poolInfo.poolSFTInfo.openFundShare, poolInfo);
    }

    function subscribe(bytes32 poolId_, uint256 currencyAmount_, uint256 openFundShareId_, uint64 expireTime_) 
        external virtual override nonReentrant returns (uint256 value_) 
    {
        require(expireTime_ > block.timestamp, "OFM: expired");

        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(poolInfo.permissionless || _whitelistStrategyManager().isWhitelisted(poolId_, _msgSender()), "OFM: not in whitelist");
        require(poolInfo.subscribeLimitInfo.fundraisingStartTime <= block.timestamp, "OFM: fundraising not started");
        require(poolInfo.subscribeLimitInfo.fundraisingEndTime >= block.timestamp, "OFM: fundraising ended");

        uint256 nav;
        if (block.timestamp < poolInfo.valueDate) {
            nav = 10 ** ERC20(poolInfo.currency).decimals();
            // only for first subscribe period
            poolInfo.fundraisingAmount += currencyAmount_;
            require(poolInfo.fundraisingAmount <= poolInfo.subscribeLimitInfo.hardCap, "OFM: hard cap reached");
        } else {
            (nav, ) = INavOracle(poolInfo.navOracle).getSubscribeNav(poolId_, block.timestamp);
        }

        value_ = (currencyAmount_ * ( 10 ** IERC3525(poolInfo.poolSFTInfo.openFundShare).valueDecimals())) / nav;
        require(value_ > 0, "OFM: value cannot be 0");

        uint256 purchasedAmount = purchasedRecords[poolId_][_msgSender()] + currencyAmount_;
		require(purchasedAmount <= poolInfo.subscribeLimitInfo.subscribeMax, "OFM: exceed subscribe max limit");
        require(currencyAmount_ >= poolInfo.subscribeLimitInfo.subscribeMin, "OFM: less than subscribe min limit");
		purchasedRecords[poolId_][_msgSender()] = purchasedAmount;

        uint256 tokenId;
        if (openFundShareId_ == 0) {
            tokenId = ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundShare)
                .mintOnlyIssueMarket(_msgSender(), poolInfo.currency, _msgSender(), poolInfo.poolSFTInfo.openFundShareSlot, value_);
        } else {
            require(IERC3525(poolInfo.poolSFTInfo.openFundShare).slotOf(openFundShareId_) == poolInfo.poolSFTInfo.openFundShareSlot, "OFM: slot not match");
            ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundShare).mintValueOnlyIssueMarket(
                _msgSender(), poolInfo.currency, openFundShareId_, value_
            );
            tokenId = openFundShareId_;
        }
		ERC20TransferHelper.doTransferIn(poolInfo.currency, _msgSender(), currencyAmount_);
        ERC20TransferHelper.doTransferOut(poolInfo.currency, payable(poolInfo.vault), currencyAmount_);

        emit Subscribe(poolId_, _msgSender(), tokenId, value_, poolInfo.currency, nav, currencyAmount_);
    }

    function requestRedeem(bytes32 poolId_, uint256 openFundShareId_, uint256 openFundRedemptionId_, uint256 redeemValue_) external virtual override nonReentrant  {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(block.timestamp > poolInfo.valueDate, "OFM: not yet redeemable");

        //only do it once per pool when the first redeem request comes in
        if (poolInfo.poolSFTInfo.latestRedeemSlot == 0) {
            IOpenFundRedemptionConcrete.RedeemInfo memory redeemInfo = IOpenFundRedemptionConcrete.RedeemInfo({
                poolId: poolId_,
                currency: poolInfo.currency,
                createTime: block.timestamp,
                nav: 0
            });
            poolInfo.poolSFTInfo.latestRedeemSlot = ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundRedemption).createSlotOnlyIssueMarket(_msgSender(), abi.encode(redeemInfo));
            _poolRedeemTokenId[poolInfo.poolSFTInfo.latestRedeemSlot] = ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundShare)
                    .mintOnlyIssueMarket(_msgSender(), poolInfo.currency, address(this), poolInfo.poolSFTInfo.openFundShareSlot, 0);
        }

        require(poolInfo.poolSFTInfo.openFundShareSlot == IERC3525(poolInfo.poolSFTInfo.openFundShare).slotOf(openFundShareId_), "OFM: invalid OpenFundShare slot");

        if (redeemValue_ == IERC3525(poolInfo.poolSFTInfo.openFundShare).balanceOf(openFundShareId_)) {
            ERC3525TransferHelper.doTransferIn(poolInfo.poolSFTInfo.openFundShare, _msgSender(), openFundShareId_);
            IERC3525(poolInfo.poolSFTInfo.openFundShare).transferFrom(openFundShareId_, _poolRedeemTokenId[poolInfo.poolSFTInfo.latestRedeemSlot], redeemValue_);
            ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundShare).burnOnlyIssueMarket(openFundShareId_, 0);
        } else {
            ERC3525TransferHelper.doTransfer(poolInfo.poolSFTInfo.openFundShare, openFundShareId_, _poolRedeemTokenId[poolInfo.poolSFTInfo.latestRedeemSlot], redeemValue_);
        }

        if (openFundRedemptionId_ == 0) {
            openFundRedemptionId_ = ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundRedemption).mintOnlyIssueMarket(_msgSender(), poolInfo.currency, _msgSender(), poolInfo.poolSFTInfo.latestRedeemSlot, redeemValue_);
        } else {
            require(poolInfo.poolSFTInfo.latestRedeemSlot == IERC3525(poolInfo.poolSFTInfo.openFundRedemption).slotOf(openFundRedemptionId_), "OFM: invalid OpenFundRedemption slot");
            ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundRedemption).mintValueOnlyIssueMarket(_msgSender(), poolInfo.currency, openFundRedemptionId_, redeemValue_);
        }

        emit RequestRedeem(poolId_, _msgSender(), openFundShareId_, openFundRedemptionId_, redeemValue_);
    }

    function revokeRedeem(bytes32 poolId_, uint256 openFundRedemptionId_) external virtual override nonReentrant {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");

        uint256 slot = IERC3525(poolInfo.poolSFTInfo.openFundRedemption).slotOf(openFundRedemptionId_);
        require(poolRedeemSlotCloseTime[slot] == 0, "OFM: slot already closed");

        uint256 value = IERC3525(poolInfo.poolSFTInfo.openFundRedemption).balanceOf(openFundRedemptionId_);
        ERC3525TransferHelper.doTransferIn(poolInfo.poolSFTInfo.openFundRedemption, _msgSender(), openFundRedemptionId_);
        OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).burnOnlyIssueMarket(openFundRedemptionId_, 0);
        uint256 shareId = ERC3525TransferHelper.doTransferOut(poolInfo.poolSFTInfo.openFundShare, _poolRedeemTokenId[slot], _msgSender(), value);
        emit RevokeRedeem(poolId_, _msgSender(), openFundRedemptionId_, shareId);
    }

    function closeCurrentRedeemSlot(bytes32 poolId_) external virtual override nonReentrant {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(_msgSender() == poolInfo.managerInfo.poolManager, "OFM: only pool manager");
        require(poolInfo.poolSFTInfo.latestRedeemSlot != 0, "OFM: no redeem requests");

        uint256 previousRedeemSlot = _previousRedeemSlot[poolId_];
        if (previousRedeemSlot > 0) {
            require(block.timestamp - poolRedeemSlotCloseTime[previousRedeemSlot] >= 24 * 60 * 60, "OFM: redeem period less than 24h");

            OpenFundRedemptionConcrete redemptionConcrete = OpenFundRedemptionConcrete(OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).concrete());
            uint256 previousRedeemNav = redemptionConcrete.getRedeemNav(previousRedeemSlot);
            require(previousRedeemNav > 0, "OFM: previous redeem nav not set");

            uint256 previousRedeemValue = redemptionConcrete.slotTotalValue(previousRedeemSlot);
            uint256 previousRepaidCurrencyAmount = redemptionConcrete.slotRepaidCurrencyAmount(previousRedeemSlot);
            uint8 redemptionValueDecimals = OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).valueDecimals();
            require(previousRepaidCurrencyAmount >= previousRedeemValue * previousRedeemNav / (10 ** redemptionValueDecimals), "OFM: previous redeem slot not fully repaid");
        }
        
        IOpenFundRedemptionConcrete.RedeemInfo memory nextRedeemInfo = IOpenFundRedemptionConcrete.RedeemInfo({
            poolId: poolId_,
            currency: poolInfo.currency,
            createTime: block.timestamp,
            nav: 0
        });

        uint256 closingRedeemSlot = poolInfo.poolSFTInfo.latestRedeemSlot;
        poolRedeemSlotCloseTime[closingRedeemSlot] = block.timestamp;
        _previousRedeemSlot[poolId_] = closingRedeemSlot;

        poolInfo.poolSFTInfo.latestRedeemSlot = ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundRedemption).createSlotOnlyIssueMarket(_msgSender(), abi.encode(nextRedeemInfo));
        _poolRedeemTokenId[poolInfo.poolSFTInfo.latestRedeemSlot] = ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundShare)
                    .mintOnlyIssueMarket(_msgSender(), poolInfo.currency, address(this), poolInfo.poolSFTInfo.openFundShareSlot, 0);
        emit CloseRedeemSlot(poolId_, closingRedeemSlot, poolInfo.poolSFTInfo.latestRedeemSlot);
    }

    function setSubscribeNav(bytes32 poolId_, uint256 time_, uint256 nav_) external virtual override {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(_msgSender() == poolInfo.managerInfo.subscribeNavManager, "OFM: only subscribe nav manager");
        INavOracle(poolInfo.navOracle).setSubscribeNavOnlyMarket(poolId_, time_, nav_);
        emit SetSubscribeNav(poolId_, time_, nav_);
    }

    function setRedeemNav(bytes32 poolId_, uint256 redeemSlot_, uint256 nav_, uint256 currencyBalance_) external virtual override nonReentrant {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(poolRedeemSlotCloseTime[redeemSlot_] > 0, "OFM: redeem slot not closed");
        require(_msgSender() == poolInfo.managerInfo.redeemNavManager, "OFM: only redeem nav manager");

        uint256 allTimeHighRedeemNav = INavOracle(poolInfo.navOracle).getAllTimeHighRedeemNav(poolId_);
        uint256 carryAmount = nav_ > allTimeHighRedeemNav ? 
                (nav_ - allTimeHighRedeemNav) * poolInfo.poolFeeInfo.carryRate * currencyBalance_ / nav_ / 10000 : 0;

        uint256 protocolFeeAmount = currencyBalance_ * protocolFeeRate * 
                (block.timestamp - poolInfo.poolFeeInfo.latestProtocolFeeSettleTime) / 10000 / (360 * 24 * 60 * 60);

        uint256 settledNav = nav_ * (currencyBalance_ - carryAmount - protocolFeeAmount) / currencyBalance_;

        uint256 mintCarryValue = carryAmount * (10 ** IERC3525(poolInfo.poolSFTInfo.openFundShare).valueDecimals()) / settledNav;
        ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundShare).mintOnlyIssueMarket(
            _msgSender(), poolInfo.currency, poolInfo.poolFeeInfo.carryCollector, poolInfo.poolSFTInfo.openFundShareSlot, mintCarryValue
        );
        emit SettleCarry(poolId_, redeemSlot_, poolInfo.currency, currencyBalance_, carryAmount);

        _mintProtocolFeeShares(poolId_, protocolFeeAmount, settledNav, 0);

        ISFTValueIssuableDelegate(poolInfo.poolSFTInfo.openFundShare).burnOnlyIssueMarket(_poolRedeemTokenId[redeemSlot_], 0);
        OpenFundRedemptionDelegate(poolInfo.poolSFTInfo.openFundRedemption).setRedeemNavOnlyMarket(redeemSlot_, settledNav);
        INavOracle(poolInfo.navOracle).setSubscribeNavOnlyMarket(poolId_, block.timestamp, settledNav);
        INavOracle(poolInfo.navOracle).updateAllTimeHighRedeemNavOnlyMarket(poolId_, nav_);

        emit SetSubscribeNav(poolId_, block.timestamp, settledNav);
        emit SetRedeemNav(poolId_, redeemSlot_, settledNav);
    }

    function settleProtocolFee(bytes32 poolId_, uint256 feeToTokenId_) external virtual nonReentrant {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        (uint256 nav, ) = INavOracle(poolInfo.navOracle).getSubscribeNav(poolId_, block.timestamp);

        uint256 totalShares = 
                OpenFundShareConcrete(OpenFundShareDelegate(poolInfo.poolSFTInfo.openFundShare).concrete()).
                slotTotalValue(poolInfo.poolSFTInfo.openFundShareSlot);

        uint256 protocolFeeAmount = 
                totalShares * nav * protocolFeeRate * (block.timestamp - poolInfo.poolFeeInfo.latestProtocolFeeSettleTime) / 
                10000 / (360 * 24 * 60 * 60) / (10 ** IERC3525(poolInfo.poolSFTInfo.openFundShare).valueDecimals());

        uint256 settledNav = nav - protocolFeeAmount * (10 ** IERC3525(poolInfo.poolSFTInfo.openFundShare).valueDecimals()) / totalShares;
        
        _mintProtocolFeeShares(poolId_, protocolFeeAmount, settledNav, feeToTokenId_);

        INavOracle(poolInfo.navOracle).setSubscribeNavOnlyMarket(poolId_, block.timestamp, settledNav);
        emit SetSubscribeNav(poolId_, block.timestamp, settledNav);
    }

    function _mintProtocolFeeShares(bytes32 poolId_, uint256 protocolFeeAmount_, uint256 settledNav_, uint256 feeToTokenId_) internal virtual {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        OpenFundShareDelegate openFundShare = OpenFundShareDelegate(poolInfo.poolSFTInfo.openFundShare);
        uint256 mintFeeValue = protocolFeeAmount_ * (10 ** openFundShare.valueDecimals()) / settledNav_;

        if (mintFeeValue > 0) {
            if (feeToTokenId_ == 0) {
                openFundShare.mintOnlyIssueMarket(
                    _msgSender(), poolInfo.currency, protocolFeeCollector, poolInfo.poolSFTInfo.openFundShareSlot, mintFeeValue
                );
            } else {
                require(openFundShare.slotOf(feeToTokenId_) == poolInfo.poolSFTInfo.openFundShareSlot, "OFM: slot not match");
                require(openFundShare.ownerOf(feeToTokenId_) == protocolFeeCollector, "OFM: owner not match");
                openFundShare.mintValueOnlyIssueMarket(
                    _msgSender(), poolInfo.currency, feeToTokenId_, mintFeeValue
                );
            }
        }

        poolInfo.poolFeeInfo.latestProtocolFeeSettleTime = uint64(block.timestamp);
        emit SettleProtocolFee(poolId_, poolInfo.currency, protocolFeeAmount_);
    }

    function removePool(bytes32 poolId_) external virtual nonReentrant {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(_msgSender() == poolInfo.managerInfo.poolManager, "OFM: only pool manager");
        require(poolInfo.fundraisingAmount == 0, "OFM: already subscribed");

        delete poolInfos[poolId_];
        emit RemovePool(poolId_);
    }

    function updateFundraisingEndTime(bytes32 poolId_, uint64 newEndTime_) external virtual nonReentrant {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(_msgSender() == owner || _msgSender() == poolInfo.managerInfo.redeemNavManager, "OFM: only owner or redeem nav manager");
        emit UpdateFundraisingEndTime(poolId_, poolInfo.subscribeLimitInfo.fundraisingEndTime, newEndTime_);
        poolInfo.subscribeLimitInfo.fundraisingEndTime = newEndTime_;
    }

	function _whitelistStrategyManager() internal view returns (IOFMWhitelistStrategyManager) {
		return IOFMWhitelistStrategyManager(
            getRequiredAddress(
                OFMConstants.CONTRACT_OFM_WHITELIST_STRATEGY_MANAGER, 
                "OFM: WhitelistStrategyManager address not found"
            )
        );
	}

    function setWhitelist(bytes32 poolId_, address[] calldata whitelist_) external virtual {
        PoolInfo storage poolInfo = poolInfos[poolId_];
        require(poolInfo.poolSFTInfo.openFundShareSlot != 0, "OFM: pool does not exist");
        require(_msgSender() == poolInfo.managerInfo.poolManager, "OFM: only manager");
        poolInfo.permissionless = whitelist_.length == 0;
		_whitelistStrategyManager().setWhitelist(poolId_, whitelist_);
	}

    function setCurrencyOnlyOwner(address currency_, bool enabled_) external virtual onlyOwner {
        require(currency_ != address(0), "OFM: currency cannot be the zero address");
		currencies[currency_] = enabled_;
		emit SetCurrency(currency_, enabled_);
	}

    function addSFTOnlyOwner(address sft_, address manager_) external virtual onlyOwner {
        require(sft_ != address(0), "OFM: sft cannot be the zero address");
		sftInfos[sft_] = SFTInfo({
            manager: manager_,
            isValid: true
        });
		emit AddSFT(sft_, manager_);
	}

    function removeSFTOnlyOwner(address sft_) external virtual onlyOwner {
        delete sftInfos[sft_];
        emit RemoveSFT(sft_);
    }

    function setProtocolFeeRateOnlyOwner(uint256 newFeeRate_) external virtual onlyOwner {
        require(newFeeRate_ <= 10000, "OFM: fee rate out of bound");
        emit SetProtocolFeeRate(protocolFeeRate, newFeeRate_);
        protocolFeeRate = newFeeRate_;
    }

    function setProtocolFeeCollectorOnlyOwner(address newFeeCollector_) external virtual onlyOwner {
        require(newFeeCollector_ != address(0), "OFM: fee collector cannot be the zero address");
        emit SetProtocolFeeCollector(protocolFeeCollector, newFeeCollector_);
        protocolFeeCollector = newFeeCollector_;
    }

    function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory) {
		bytes32[] memory existAddresses = super._resolverAddressesRequired();
		bytes32[] memory newAddresses = new bytes32[](2);
		newAddresses[0] = OFMConstants.CONTRACT_OFM_WHITELIST_STRATEGY_MANAGER;
		newAddresses[1] = OFMConstants.CONTRACT_OFM_NAV_ORACLE;
		return _combineArrays(existAddresses, newAddresses);
	}

    function _validateInputPoolInfo(InputPoolInfo calldata inputPoolInfo_) internal view virtual {
        require(currencies[inputPoolInfo_.currency], "OFM: currency not allowed");
        SFTInfo storage openFundShareInfo = sftInfos[inputPoolInfo_.openFundShare];
        require(openFundShareInfo.isValid, "OFM: share not allowed");
        require(openFundShareInfo.manager == address(0) || _msgSender() == openFundShareInfo.manager, "OFM: invalid share manager");

        SFTInfo storage openFundRedemptionInfo = sftInfos[inputPoolInfo_.openFundRedemption];
        require(openFundRedemptionInfo.isValid, "OFM: redemption not allowed");
        require(openFundRedemptionInfo.manager == address(0) || _msgSender() == openFundRedemptionInfo.manager, "OFM: invalid redemption manager");

        require(
            IERC3525(inputPoolInfo_.openFundShare).valueDecimals() == IERC3525(inputPoolInfo_.openFundRedemption).valueDecimals(), 
            "OFM: valueDecimals not match"
        );
        
        require(inputPoolInfo_.subscribeLimitInfo.subscribeMin <= inputPoolInfo_.subscribeLimitInfo.subscribeMax, "OFM: invalid min and max");
        require(inputPoolInfo_.subscribeLimitInfo.fundraisingStartTime <= inputPoolInfo_.valueDate, "OFM: invalid valueDate");
        require(inputPoolInfo_.subscribeLimitInfo.fundraisingStartTime <= inputPoolInfo_.subscribeLimitInfo.fundraisingEndTime, "OFM: invalid startTime and endTime");
        require(inputPoolInfo_.subscribeLimitInfo.fundraisingEndTime > block.timestamp, "OFM: invalid endTime");

        require(inputPoolInfo_.vault != address(0), "OFM: invalid vault");
        require(inputPoolInfo_.carryCollector != address(0), "OFM: invalid carryCollector");
        require(inputPoolInfo_.subscribeNavManager != address(0), "OFM: invalid subscribeNavManager");
        require(inputPoolInfo_.redeemNavManager != address(0), "OFM: invalid redeemNavManager");
        require(inputPoolInfo_.carryRate <= 10000, "OFM: invalid carryRate");
    }
}