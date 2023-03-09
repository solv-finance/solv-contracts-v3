// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import "@solvprotocol/contracts-v3-solidity-utils/contracts/access/AdminControl.sol";

abstract contract FactoryCore is AdminControl {

    event NewDefaultAdmin(address indexed newDefaultAdmin);
    event NewImplementation(address indexed implementation);
    event NewBeacon(address indexed beacon, address indexed implementation);
    event UpgradeBeacon(address indexed beacon, address indexed newImplementation);
    event NewBeaconProxy(string indexed name, address indexed beaconProxy);
    event SetManager(address indexed manager, bool enabled);

    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    EnumerableSetUpgradeable.AddressSet internal _managers;

    address private _self;

    address public defaultAdmin;

    address public implementation;
    address public beacon;
    mapping(string => address) public beaconProxies;

    modifier onlyManagers() {
        require(
            _msgSender() == admin || _managers.contains(_msgSender())
        );
        _;
    }

    function __FactoryCore_init() internal onlyInitializing {
        __AdminControl_init(_msgSender());
        _self = address(this);
        setDefaultAdmin(_msgSender());
    }

    function setImplementation(address implementation_) public virtual onlyAdmin {
        implementation = implementation_;
        emit NewImplementation(implementation_);
    }

    function deployBeacon() public virtual onlyAdmin returns (address) {
        require(beacon == address(0), "beacon already deployed");
        require(implementation != address(0), "implementation not deployed");
        beacon = address(new UpgradeableBeacon(implementation));
        emit NewBeacon(beacon, implementation);
        return beacon;
    }

    function setBeacon(address newBeacon_) public virtual onlyAdmin {
        beacon = newBeacon_;
        emit NewBeacon(newBeacon_, UpgradeableBeacon(beacon).implementation());
    }

    function transferBeaconOwnership(address newBeaconOwner_) public virtual onlyAdmin {
        require(beacon != address(0), "beacon not deployed");
        UpgradeableBeacon(beacon).transferOwnership(newBeaconOwner_);
    }

    function upgradeBeacon() public virtual onlyAdmin {
        require(implementation != address(0), "implementation not deployed");
        require(UpgradeableBeacon(beacon).implementation() != implementation, "same implementation");
        UpgradeableBeacon(beacon).upgradeTo(implementation);
        emit UpgradeBeacon(beacon, implementation);
    }

    function deployBeaconProxy(string memory productName_, bytes memory data_) public virtual onlyManagers returns (address beaconProxy) {
        require(beaconProxies[productName_] == address(0), "product already deployed");
        require(beacon != address(0), "beacon not deployed");

        bytes32 salt = keccak256(abi.encodePacked(productName_));
        beaconProxy = address(new BeaconProxy{salt: salt}(beacon, new bytes(0)));
        beaconProxies[productName_] = beaconProxy;

        AddressUpgradeable.functionCall(
            beaconProxy,
            data_,
            "initialize failed"
        );

        AddressUpgradeable.functionCall(
            beaconProxy,
            abi.encodeWithSelector(
                bytes4(keccak256("setPendingAdmin(address)")),
                defaultAdmin
            ),
            "set pending admin failed"
        );

        emit NewBeaconProxy(productName_, beaconProxy);
    }

    function importBeaconProxy(string memory productName_, address beaconProxyAddress_) public virtual onlyManagers {
        require(beacon != address(0), "beacon not deployed");
        beaconProxies[productName_] = beaconProxyAddress_;
        emit NewBeaconProxy(productName_, beaconProxyAddress_);
    }

    function setDefaultAdmin(address newDefaultAdmin_) public virtual onlyAdmin {
        defaultAdmin = newDefaultAdmin_;
        emit NewDefaultAdmin(newDefaultAdmin_);
    }

    function setManager(address manager_, bool enabled_) public virtual onlyAdmin {
        if (enabled_) {
            _managers.add(manager_);
        } else {
            _managers.remove(manager_);
        }
        emit SetManager(manager_, enabled_);
    }
}