// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@solvprotocol/erc-3525/IERC3525.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/misc/Constants.sol";
import "@solvprotocol/contracts-v3-sft-core/contracts/BaseSFTConcreteUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./ITimelockedERC20Concrete.sol";

abstract contract TimelockedERC20Concrete is ITimelockedERC20Concrete, BaseSFTConcreteUpgradeable {

	event SetStartTime(uint256 indexed slot, uint64 oldStartTime, uint64 newStartTime);

	mapping(uint256 => TimelockSlotInfo) internal _slotInfos;
	mapping(uint256 => uint256) internal _tokenInitialValue;

	function __TimelockedERC20Concrete_init() internal onlyInitializing {
		__BaseSFTConcrete_init();
	}

    function createSlotOnlyDelegate(address txSender_, address erc20_, bytes calldata inputSlotInfo_) external virtual override onlyDelegate returns (uint256) {
		return _createSlot(txSender_, erc20_, inputSlotInfo_);
	}

	function mintOnlyDelegate(address /** txSender_ */, address /** mintTo_ */, uint256 slot_, uint256 tokenId_, uint256 value_) external virtual override onlyDelegate {
		require(_isSlotValid(slot_), "TimelockedERC20Concrete: invalid slot");
		_tokenInitialValue[tokenId_] += value_;
		_slotInfos[slot_].totalValue += value_;
	}

	function claimOnlyDelegate(uint256 tokenId_, address erc20_, uint256 claimValue_) external virtual onlyDelegate {
		uint256 slot = IERC3525(delegate()).slotOf(tokenId_);
		require(_slotInfos[slot].erc20 == erc20_, "TimelockedERC20Concrete: erc20 not match");
		uint256 claimable = claimableValue(tokenId_);
		require(claimValue_ <= claimable, "TimelockedERC20Concrete: over claim");
		_slotInfos[slot].totalValue -= claimValue_;
	}

	function transferOnlyDelegate(uint256 fromTokenId_, uint256 toTokenId_, uint256 transferValue_) external virtual override onlyDelegate {
		uint256 fromTokenValue = IERC3525(delegate()).balanceOf(fromTokenId_);
		uint256 transferInitialValue = transferValue_ * _tokenInitialValue[fromTokenId_] / fromTokenValue;
		_tokenInitialValue[fromTokenId_] = _tokenInitialValue[fromTokenId_] - transferInitialValue;
		_tokenInitialValue[toTokenId_] = _tokenInitialValue[toTokenId_] + transferInitialValue;
	}

	function setStartTimeOnlyDelegate(uint256 slot_, uint64 startTime_) external virtual override onlyDelegate {
		TimelockSlotInfo storage info = _slotInfos[slot_];
		require(info.isValid, "TimelockedERC20Concrete: invalid slot");
		require(startTime_ <= info.latestStartTime, "TimelockedERC20Concrete: exceeds latestStartTime");
		require(
			(info.startTime == 0 && block.timestamp < info.latestStartTime) || block.timestamp < info.startTime, 
			"TimelockedERC20Concrete: already started"
		);

		emit SetStartTime(slot_, info.startTime == 0 ? info.latestStartTime : info.startTime, startTime_);
		info.startTime = startTime_;
	}

	function getSlot(
		address erc20_, TimelockType timelockType_, uint64 latestStartTime_, 
		address issuer_, uint64[] memory terms, uint32[] memory percentages_
	) public view virtual returns (uint256) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return uint256(keccak256(abi.encode(chainId, delegate(), erc20_, timelockType_, latestStartTime_, issuer_, terms, percentages_)));
    }

	function slotInfo(uint256 slot) external view override returns (TimelockSlotInfo memory) {
		return _slotInfos[slot];
	}

	function erc20(uint256 slot_) external view virtual override returns (address) {
		return _slotInfos[slot_].erc20;
	}

	function issuer(uint256 slot_) external view virtual override returns (address) {
		return _slotInfos[slot_].issuer;
	}

	function tokenInitialValue(uint256 tokenId_) external view virtual override returns (uint256) {
		return _tokenInitialValue[tokenId_];
	}

	function claimableValue(uint256 tokenId_) public view virtual returns (uint256) {
		uint256 slot = IERC3525(delegate()).slotOf(tokenId_);
		TimelockSlotInfo memory info = _slotInfos[slot];
		uint64 startTime = info.startTime == 0 ? info.latestStartTime : info.startTime;

		if (!info.isValid || block.timestamp < startTime) {
			return 0;
		}

		uint256 balance = IERC3525(delegate()).balanceOf(tokenId_);

		if (info.timelockType == TimelockType.ONE_TIME) {
			return block.timestamp >= startTime + info.terms[0] ? balance : 0;

		} else if (info.timelockType == TimelockType.LINEAR) {
			if (block.timestamp >= startTime + info.terms[0]) {
				return balance;
			}

			uint256 timeRemained = startTime + info.terms[0] - block.timestamp;
			uint256 lockedValue = _tokenInitialValue[tokenId_] * timeRemained / info.terms[0];
			return balance > lockedValue ? balance - lockedValue : 0;

		} else if (info.timelockType == TimelockType.STAGED) {
			uint64 timeNode = startTime;
			uint256 unlockedPercentage = 0;
			for (uint256 termIndex = 0; termIndex < info.terms.length; termIndex++) {
				timeNode += info.terms[termIndex];
				if (block.timestamp >= timeNode) {
					unlockedPercentage += info.percentages[termIndex];
				} else {
					break;
				}
			}
			
			uint256 lockedValue = _tokenInitialValue[tokenId_] - _tokenInitialValue[tokenId_] * unlockedPercentage / Constants.FULL_PERCENTAGE;
			return balance > lockedValue ? balance - lockedValue : 0;

		} else {
			revert("TimelockedERC20Concrete: invalid timelock type");
		}
	}

	function _validateSlotInfo(TimelockSlotInfo memory slotInfo_) internal view virtual {
		require(ERC20(slotInfo_.erc20).decimals() <= 18, "TimelockedERC20Concrete: unsupported erc20 decimals");
        require(slotInfo_.latestStartTime < 4102416000, "TimelockedERC20Concrete: irrational startTime");
        require(slotInfo_.terms.length == slotInfo_.percentages.length, "TimelockedERC20Concrete: array length mismatch");

		if (slotInfo_.timelockType == TimelockType.LINEAR || slotInfo_.timelockType == TimelockType.ONE_TIME) {
			require(
				slotInfo_.percentages.length == 1 && slotInfo_.percentages[0] == Constants.FULL_PERCENTAGE, 
				"TimelockedERC20Concrete: invalid percentage values"
			);

		} else if (slotInfo_.timelockType == TimelockType.STAGED) {
			require(
				slotInfo_.percentages.length > 1 && slotInfo_.percentages.length <= 50, 
				"TimelockedERC20Concrete: invalid percentages length"
			);

			uint256 sumOfPercentages = 0;
			for (uint256 i = 0; i < slotInfo_.percentages.length; i++) {
				sumOfPercentages += slotInfo_.percentages[i];
			}
			require(sumOfPercentages == Constants.FULL_PERCENTAGE, "TimelockedERC20Concrete: percentages not 100%");

		} else {
			revert("TimelockedERC20Concrete: invalid timelock type");
		}
    }

	function _isSlotValid(uint256 slot_) internal view virtual override returns (bool) {
		return _slotInfos[slot_].isValid;
	}
	
	function _createSlot(address txSender_, address erc20_, bytes memory inputSlotInfo_) internal virtual returns (uint256 slot_);

	uint256[48] private __gap;
}