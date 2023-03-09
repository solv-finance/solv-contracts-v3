// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/access/OwnControl.sol";
import "@solvprotocol/erc-3525/periphery/ERC3525MetadataDescriptor.sol";
import "./EarnDelegate.sol";
import "./EarnConcrete.sol";
import "./svgs/DefaultPayableSVG.sol";

contract PayableMetadataDescriptor is ERC3525MetadataDescriptor, Initializable, OwnControl {

    using Strings for uint256;
    using Strings for address;

    event SetPayableSVG(
        address indexed payableAddress,
        address oldPayableSVG,
        address newPayableSVG
    );

    mapping(address => address) internal _payableSVGs;

    function initialize(address owner_, address defaultPayableSVG_) external initializer {
        OwnControl.__OwnControl_init(owner_);
        _setPayableSVG(address(0), defaultPayableSVG_);
    }

    function setPayableSVG(address payableAddress_, address payableSVG_) public onlyOwner {
        _setPayableSVG(payableAddress_, payableSVG_);
    }

    function _setPayableSVG(address payableAddress_, address payableSVG_) internal {
        emit SetPayableSVG(payableAddress_, _payableSVGs[payableAddress_], payableSVG_);
        _payableSVGs[payableAddress_] = payableSVG_;
    }

    function getPayableSVG(address payableAddress_) external view returns (address) {
        address payableSVG = _payableSVGs[payableAddress_];
        if (payableSVG == address(0)) {
            payableSVG = _payableSVGs[address(0)];
        }
        return payableSVG;
    }

    function _tokenName(uint256 tokenId_) internal view virtual override returns (string memory) {
        EarnDelegate delegate = EarnDelegate(msg.sender);
        return string(abi.encodePacked(delegate.name(), " #", tokenId_.toString()));
    }

    function _tokenImage(uint256 tokenId_) internal view virtual override returns (bytes memory) {
        address payableSVG = _payableSVGs[_msgSender()];
        if (payableSVG == address(0)) {
            payableSVG = _payableSVGs[address(0)];
        }

        return 
            abi.encodePacked(
                'data:image/svg+xml;base64,',
                Base64.encode(bytes(DefaultPayableSVG(payableSVG).generateSVG(_msgSender(), tokenId_)))
            );
    }

    function _slotProperties(uint256 slot_) internal view virtual override returns (string memory) {
        EarnDelegate delegate = EarnDelegate(msg.sender);
        EarnConcrete concrete = EarnConcrete(delegate.concrete());

        EarnConcrete.SlotBaseInfo memory baseInfo = concrete.slotBaseInfo(slot_);
        EarnConcrete.SlotExtInfo memory extInfo = concrete.slotExtInfo(slot_);

        uint256 slotTotalValue = concrete.slotTotalValue(slot_);
        uint256 repaidCurrencyAmount = concrete.repaidCurrencyAmount(slot_);

        uint256 chainId;
        assembly {
            chainId := chainid()
        }

        return 
            string(
                /* solhint-disable */
                abi.encodePacked(
                    '[',
                        abi.encodePacked(
                            '{"name":"chain_id",',
                            '"description":"chain id",',
                            '"value":"', chainId.toString(), '",',
                            '"is_intrinsic":true,',
                            '"order":1,', 
                            '"display_type":"number"},'
                        ),
                        abi.encodePacked(
                            '{"name":"payable_token_address",',
                            '"description":"Address of this contract.",',
                            '"value":"', address(delegate).toHexString(), '",',
                            '"is_intrinsic":true,',
                            '"order":2,', 
                            '"display_type":"string"},'
                        ),
                        abi.encodePacked(
                            '{"name":"issuer",',
                            '"description":"Issuer of this slot.",',
                            '"value":"', baseInfo.issuer.toHexString(), '",',
                            '"is_intrinsic":true,',
                            '"order":3,', 
                            '"display_type":"string"},'
                        ),
                        abi.encodePacked(
                            '{"name":"currency",',
                            '"description":"Currency of this slot.",',
                            '"value":"', baseInfo.currency.toHexString(), '",',
                            '"is_intrinsic":true,',
                            '"order":4,', 
                            '"display_type":"string"},'
                        ),
                        abi.encodePacked(
                            '{"name":"interest_rate",',
                            '"description":"Interest rate of this slot.",',
                            '"value":', uint256(baseInfo.interestRate).toString(), ',',
                            '"is_intrinsic":true,',
                            '"order":5,', 
                            '"display_type":"number"},'
                        ),
                        abi.encodePacked(
                            '{"name":"value_date",',
                            '"description":"Value date of this slot.",',
                            '"value":', uint256(baseInfo.valueDate).toString(), ',',
                            '"is_intrinsic":true,',
                            '"order":6,', 
                            '"display_type":"date"},'
                        ),
                        abi.encodePacked(
                            '{"name":"maturity",',
                            '"description":"Maturity date of this slot.",',
                            '"value":', uint256(baseInfo.maturity).toString(), ',',
                            '"is_intrinsic":true,',
                            '"order":7,', 
                            '"display_type":"date"},'
                        ),
                        abi.encodePacked(
                            '{"name":"transferable",',
                            '"description":"Indicate if tokens of this slot are transferable.",',
                            '"value":', baseInfo.transferable ? 'true' : 'false', ',',
                            '"is_intrinsic":true,',
                            '"order":8,', 
                            '"display_type":"boolean"},'
                        ),

                        abi.encodePacked(
                            abi.encodePacked(
                                '{"name":"issue_quota",',
                                '"description":"Issue quota of this slot.",',
                                '"value":', uint256(extInfo.issueQuota).toString(), ',',
                                '"is_intrinsic":false,',
                                '"display_type":"number"},'
                            ),
                            abi.encodePacked(
                                '{"name":"total_value",',
                                '"description":"Total issued value of this slot.",',
                                '"value":', slotTotalValue.toString(), ',',
                                '"is_intrinsic":false,',
                                '"display_type":"number"},'
                            ),
                            abi.encodePacked(
                                '{"name":"repaid_amount",',
                                '"description":"Repaid amount of this slot.",',
                                '"value":', repaidCurrencyAmount.toString(), ',',
                                '"is_intrinsic":false,',
                                '"display_type":"number"},'
                            ),
                            abi.encodePacked(
                                '{"name":"external_url",',
                                '"description":"External URI of this slot.",',
                                '"value":"', extInfo.externalURI, '",',
                                '"is_intrinsic":false,',
                                '"display_type":"string"}'
                            )
                        ),
                    ']'
                )
                /* solhint-enable */
            );
    }

    function _tokenProperties(uint256 tokenId_) internal view virtual override returns (string memory) {
        EarnDelegate delegate = EarnDelegate(msg.sender);
        EarnConcrete concrete = EarnConcrete(delegate.concrete());

        uint256 slot = delegate.slotOf(tokenId_);
        EarnConcrete.SlotBaseInfo memory baseInfo = concrete.slotBaseInfo(slot);

        return 
            string(
                abi.encodePacked(
                    /* solhint-disable */
                    '{"issuer":"', baseInfo.issuer.toHexString(),
                    '","currency":"', baseInfo.currency.toHexString(),
                    '","interest_rate":', uint256(baseInfo.interestRate).toString(),
                    ',"value_date":', uint256(baseInfo.valueDate).toString(),
                    ',"maturity":', uint256(baseInfo.maturity).toString(),
                    '}'
                    /* solhint-enable */
                )
            );
    }
}