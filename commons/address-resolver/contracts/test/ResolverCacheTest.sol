// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-solidity-utils/contracts/access/OwnControl.sol";
import "../ResolverCache.sol";

contract ResolverCacheTest is ResolverCache, OwnControl {
	bytes32 internal _contractName;
	function initialize(address resolver_) external initializer {
		__ResolverCache_init(resolver_);
	}

	function setAddressRequired(bytes32 name_) external {
		_contractName = name_;
	}
	 function _resolverAddressesRequired() internal view virtual override returns (bytes32[] memory addresses) { 
		console.logString("ok1");
		bytes32[] memory existAddresses = super._resolverAddressesRequired();
		bytes32[] memory newAddresses = new bytes32[](1);
		newAddresses[0] = _contractName;
		console.logString("ok2");
		return _combineArrays(existAddresses, newAddresses);	
	 }
}