// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./FactoryCore.sol";
import "./EarnConcreteFactory.sol";
import "../EarnDelegate.sol";

contract EarnDelegateFactory is FactoryCore {

    address public payableConcreteFactory;

    address public addressResolver;
    address public payableMetadataDescriptor;
    address public payableDelegateOwner;

    function initialize(
        address payableConcreteFactory_, 
        address addressResolver_,
        address payableMetadataDescriptor_,
        address payableDelegateOwner_
    ) external initializer {
        FactoryCore.__FactoryCore_init();
        payableConcreteFactory = payableConcreteFactory_;
        addressResolver = addressResolver_;
        payableMetadataDescriptor = payableMetadataDescriptor_;
        payableDelegateOwner = payableDelegateOwner_;
    }

    function deployPayableDelegate(
        string memory productName_, string memory name_, string memory symbol_, uint8 decimals_, 
        address concrete_, bool allowRepayWithBalance_
    ) public virtual returns (address payableDelegate_) {
        payableDelegate_ = deployBeaconProxy(
            productName_,
            abi.encodeWithSelector(
                bytes4(keccak256("initialize(address,string,string,uint8,address,address,address,bool)")),
                addressResolver, name_, symbol_, decimals_, concrete_, 
                payableMetadataDescriptor, payableDelegateOwner, allowRepayWithBalance_
            )
        );

        Address.functionCall(
            payableDelegate_,
            abi.encodeWithSelector(bytes4(keccak256("rebuildCache()"))),
            "failed to rebuild cache"
        );
    }

    function deployPayableProduct(
        string memory productName_, string memory name_, string memory symbol_, uint8 decimals_, bool allowRepayWithBalance_
    ) external virtual returns (address payableConcrete_, address payableDelegate_) {
        payableConcrete_ = EarnConcreteFactory(payableConcreteFactory).deployPayableConcrete(productName_);
        payableDelegate_ = deployPayableDelegate(productName_, name_, symbol_, decimals_, payableConcrete_, allowRepayWithBalance_);
    }

    function setAddressResolver(address addressResolver_) external virtual onlyAdmin {
        addressResolver = addressResolver_;
    }

    function setPayableMetadataDescriptor(address payableMetadataDescriptor_) external virtual onlyAdmin {
        payableMetadataDescriptor = payableMetadataDescriptor_;
    }

    function setPayableDelegateOwner(address payableDelegateOwner_) external virtual onlyAdmin {
        payableDelegateOwner = payableDelegateOwner_;
    }
}