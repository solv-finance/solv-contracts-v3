const { ethers } = require('hardhat');

const AddressResolverName = {
  OPEN_FUND_MARKET: ethers.utils.formatBytes32String('OpenFundMarket'),
  NAV_ORACLE: ethers.utils.formatBytes32String('OFMNavOracle'),
  WHITELIST_MANAGER: ethers.utils.formatBytes32String('OFMWhitelistStrategyManager'),
}

module.exports = {
  AddressResolverName,
}