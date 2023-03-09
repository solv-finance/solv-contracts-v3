// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTDelegateUpgradeable.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/helpers/ERC20TransferHelper.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IMultiRechargeableDelegate.sol";
import "./IMultiRechargeableConcrete.sol";

abstract contract MultiRechargeableDelegate is IMultiRechargeableDelegate, BaseSFTDelegateUpgradeable {

	function recharge(uint256 slot_, address currency_, uint256 amount_) external payable virtual override nonReentrant {
		IMultiRechargeableConcrete(concrete()).rechargeOnlyDelegate(slot_, currency_, amount_);
        ERC20TransferHelper.doTransferIn(currency_, _msgSender(), amount_);
		emit Recharge(slot_, currency_, amount_);
	}

	function claimTo(address to_, uint256 tokenId_, address currency_, uint256 amount_) external virtual override nonReentrant {
        require(_isApprovedOrOwner(_msgSender(), tokenId_), "MultiRechargeableDelegate: caller is not owner nor approved");
		
		// uint256 claimable = IMultiRechargeableConcrete(concrete()).claimableAmount(tokenId_);
		// require(amount_ <= claimable, "MultiRechargeableDelegate: insufficient amount to claim");
		IMultiRechargeableConcrete(concrete()).claimOnlyDelegate(tokenId_, currency_, amount_);

		uint256 balance = IERC20(currency_).balanceOf(address(this));
		if (amount_ > balance) {
			amount_ = balance;
		}

        ERC20TransferHelper.doTransferOut(currency_, payable(to_), amount_);
		emit Claim(to_, tokenId_, currency_, amount_);
	}

    function _beforeValueTransfer(
        address from_,
        address to_,
        uint256 fromTokenId_,
        uint256 toTokenId_,
        uint256 slot_,
        uint256 value_
    ) internal virtual override(ERC3525SlotEnumerableUpgradeable) {
        super._beforeValueTransfer(from_, to_, fromTokenId_, toTokenId_, slot_, value_);

		if (from_ == address(0) && fromTokenId_ == 0) {
			IMultiRechargeableConcrete(concrete()).mintOnlyDelegate(toTokenId_, slot_, value_);
		}

		if (from_ != address(0) && fromTokenId_ != 0 && to_ != address(0) && toTokenId_ != 0) {
            IMultiRechargeableConcrete(concrete()).transferOnlyDelegate(fromTokenId_, toTokenId_, 
                ERC3525Upgradeable.balanceOf(fromTokenId_), value_);
		}
    }

	uint256[50] private __gap;
}