// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

abstract contract SerialIdGenerator {

	uint256 public currentTokenId;

	function _createSerialId() internal virtual returns(uint256) {
		currentTokenId++;
		return currentTokenId;
	}

	uint256[49] private __gap;
}