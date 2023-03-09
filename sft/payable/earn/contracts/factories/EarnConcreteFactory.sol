// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./FactoryCore.sol";
import "../EarnConcrete.sol";

contract EarnConcreteFactory is FactoryCore {

    function initialize() external initializer {
        FactoryCore.__FactoryCore_init();
    }

    function deployPayableConcrete(string memory productName_) external virtual returns (address) {
        return deployBeaconProxy(
            productName_,
            abi.encodeWithSelector(
                bytes4(keccak256("initialize()"))
            )
        );
    }

}