// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-solidity-utils/contracts/misc/Constants.sol";
import "@solvprotocol/contracts-v3-address-resolver/contracts/ResolverCache.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/multi-rechargeable/MultiRechargeableDelegate.sol";
import "@solvprotocol/contracts-v3-sft-abilities/contracts/mintable/SFTMintableDelegate.sol";

contract UnderwriterProfitDelegate is SFTMintableDelegate, MultiRechargeableDelegate, ResolverCache {
	function initialize(address resolver_, string memory name_, string memory symbol_, uint8 decimals_, 
		address concrete_, address metadata_, address owner_) external initializer {
		__SFTMintableDelegate_init(name_, symbol_, decimals_, concrete_, metadata_, owner_);
		__ResolverCache_init(resolver_);
	}

	function _beforeCreateSlot(bytes memory /** inputSlotInfo_ */) internal virtual override {
		require(msg.sender == _issueMarket(), "UnderwriterProfit: only issue market can create slot");
	}

	function _beforeMint(address /** mintTo_ */, uint256 /** slot_ */, uint256 /** value_ */) internal virtual override {
		require(msg.sender == _issueMarket(), "UnderwriterProfit: only issue market can mint");
	}

	function _beforeValueTransfer( address from_, address to_, uint256 fromTokenId_, uint256 toTokenId_,
        uint256 slot_, uint256 value_) internal virtual override(ERC3525SlotEnumerableUpgradeable, MultiRechargeableDelegate) {
		MultiRechargeableDelegate._beforeValueTransfer(from_, to_, fromTokenId_, toTokenId_, slot_, value_);
	}

	function _issueMarket() internal view returns(address) {
		return getRequiredAddress(Constants.CONTRACT_ISSUE_MARKET, "UnderwriterProfit: Issue market not set");
	}

	function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory) {
		bytes32[] memory existAddresses = super._resolverAddressesRequired();
		bytes32[] memory newAddresses = new bytes32[](1);
		newAddresses[0] = Constants.CONTRACT_ISSUE_MARKET;
		return _combineArrays(existAddresses, newAddresses);
	}
}