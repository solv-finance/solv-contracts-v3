// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-abilities/contracts/fcfs-multi-repayable/FCFSMultiRepayableDelegate.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/value-issuable/SFTValueIssuableDelegate.sol";
import "./IOpenFundRedemptionDelegate.sol";
import "./IOpenFundRedemptionConcrete.sol";

contract OpenFundRedemptionDelegate is IOpenFundRedemptionDelegate, SFTValueIssuableDelegate, FCFSMultiRepayableDelegate {

	bytes32 internal constant CONTRACT_OPEN_FUND_MARKET = "OpenFundMarket"; 

    bool private __allowRepayWithBalance;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() { 
        _disableInitializers();
    }
    
	function initialize(
        address resolver_, string calldata name_, string calldata symbol_, uint8 decimals_, 
		address concrete_, address descriptor_, address owner_, bool allowRepayWithBalance_
    ) external initializer {
		__SFTIssuableDelegate_init(resolver_, name_, symbol_, decimals_, concrete_, descriptor_, owner_);
        __allowRepayWithBalance = allowRepayWithBalance_;
	}

	function setRedeemNavOnlyMarket(uint256 slot_, uint256 nav_) external virtual override {
		require(_msgSender() == _issueMarket(), "OFRD: only market");
		IOpenFundRedemptionConcrete(concrete()).setRedeemNavOnlyDelegate(slot_, nav_);
	}

    function claimTo(address to_, uint256 tokenId_, address currency_, uint256 claimValue_) external virtual override nonReentrant {
        require(claimValue_ > 0, "OFRD: claim value is zero");
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "OFRD: caller is not owner nor approved");
        uint256 slot = ERC3525Upgradeable.slotOf(tokenId_);
        uint256 claimableValue = IFCFSMultiRepayableConcrete(concrete()).claimableValue(tokenId_);
        require(claimValue_ <= claimableValue, "OFRD: over claim");
        
        uint256 claimCurrencyAmount = IFCFSMultiRepayableConcrete(concrete()).claimOnlyDelegate(tokenId_, slot, currency_, claimValue_);
        uint256 feeRate = IOpenFundRedemptionConcrete(concrete()).getRedemptionFeeRate(slot);
        uint256 feeAmount = claimCurrencyAmount * feeRate / 1e18;
        
        if (claimValue_ == ERC3525Upgradeable.balanceOf(tokenId_)) {
            ERC3525Upgradeable._burn(tokenId_);
        } else {
            ERC3525Upgradeable._burnValue(tokenId_, claimValue_);
        }
        
        address feeReceiver = IOpenFundRedemptionConcrete(concrete()).redemptionFeeReceiver();
        if (feeReceiver != address(0) && feeAmount > 0) {
            ERC20TransferHelper.doTransferOut(currency_, payable(feeReceiver), feeAmount);
        }
        ERC20TransferHelper.doTransferOut(currency_, payable(to_), claimCurrencyAmount - feeAmount);
        emit Claim(to_, tokenId_, claimValue_, currency_, claimCurrencyAmount);
    }

    function allowRepayWithBalance() public view virtual override returns (bool) {
        return __allowRepayWithBalance;
    }

	function _beforeValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal virtual override(ERC3525SlotEnumerableUpgradeable, FCFSMultiRepayableDelegate) {
        FCFSMultiRepayableDelegate._beforeValueTransfer(from_, to_, fromTokenId_, toTokenId_, slot_, value_);
    }

	function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory addressNames) {
		addressNames = new bytes32[](1);
		addressNames[0] = CONTRACT_OPEN_FUND_MARKET;
	}

	function _issueMarket() internal view virtual override returns (address) {
		return getRequiredAddress(CONTRACT_OPEN_FUND_MARKET, "OFRD: OpenFundMarket not set");
	}

	function contractType() external view virtual override returns (string memory) {
        return "Open Fund Redemptions";
    }
}