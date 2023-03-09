// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@solvprotocol/contracts-v3-solidity-utils/contracts/access/OwnControl.sol";
import "./IAddressResolver.sol";
import "./ResolverCache.sol";

contract AddressResolver is IAddressResolver, OwnControl {
	event AddressImported(bytes32 indexed name, address indexed addr);

	mapping(bytes32 => address) internal addresses;

	function initialize(address owner_) external initializer {
		__OwnControl_init(owner_);
	}

	function importAddressesOnlyOwner(bytes32[] calldata names_, address[] calldata addresses_) external onlyOwner {
		require(names_.length == addresses_.length, "AddressResolver: names and addresses length not match");

		for (uint256 i = 0; i < names_.length; i++) {
			bytes32 name = names_[i];
			address addr = addresses_[i];
			addresses[name] = addr;
			emit AddressImported(name, addr);
		}
	}

	function getAddress(bytes32 name) external view override returns (address) {
		return addresses[name];
	}
	function getRequiredAddress(bytes32 name, string calldata reason) external view override returns (address) {
		address addr = addresses[name];
		require(addr != address(0), reason);
		return addr;
	}

	function rebuildCaches(ResolverCache[] calldata caches) external {
		for (uint256 i = 0; i < caches.length; i++) {
			caches[i].rebuildCache();
		}
	}
}