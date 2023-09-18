const { ethers } = require('hardhat');
const colors = require('colors');
const { AddressResolverName } = require('./commons.js');
const path = require("path");

const ProxyAdminBin = require('@openzeppelin/upgrades-core/artifacts/@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol/ProxyAdmin.json');
const TransparentUpgradeableProxyBin = require('@openzeppelin/upgrades-core/artifacts/@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol/TransparentUpgradeableProxy.json');

const ERC20MockBin = require('@solvprotocol/contracts-v3-mocks/artifacts/contracts/ERC20Mock.sol/ERC20Mock.json');
const AddressResolverBin = require('@solvprotocol/contracts-v3-address-resolver/artifacts/contracts/AddressResolver.sol/AddressResolver.json');

const NavOracleBin = require('@solvprotocol/contracts-v3-open-fund-market/artifacts/contracts/oracle/NavOracle.sol/NavOracle.json');
const WhitelistStrategyManagerBin = require('@solvprotocol/contracts-v3-open-fund-market/artifacts/contracts/whitelist/OFMWhitelistStrategyManager.sol/OFMWhitelistStrategyManager.json');
const OpenFundMarketBin = require('@solvprotocol/contracts-v3-open-fund-market/artifacts/contracts/OpenFundMarket.sol/OpenFundMarket.json');
const OpenFundMarketDBG = require('@solvprotocol/contracts-v3-open-fund-market/artifacts/contracts/OpenFundMarket.sol/OpenFundMarket.dbg.json');

const SVGBackgroundGeneratorBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/svg-base/SVGBackgroundGenerator.sol/SVGBackgroundGenerator.json');

const DefaultOpenFundShareSVGBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-shares/svgs/DefaultOpenFundShareSVG.sol/DefaultOpenFundShareSVG.json');
const OpenFundShareMetadataDescriptorBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-shares/OpenFundShareMetadataDescriptor.sol/OpenFundShareMetadataDescriptor.json');
const OpenFundShareDelegateBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-shares/OpenFundShareDelegate.sol/OpenFundShareDelegate.json');
const OpenFundShareConcreteBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-shares/OpenFundShareConcrete.sol/OpenFundShareConcrete.json');
const OpenFundShareDelegateDBG = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-shares/OpenFundShareDelegate.sol/OpenFundShareDelegate.dbg.json');

const DefaultOpenFundRedemptionSVGBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-redemptions/svgs/DefaultOpenFundRedemptionSVG.sol/DefaultOpenFundRedemptionSVG.json');
const OpenFundRedemptionMetadataDescriptorBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-Redemptions/OpenFundRedemptionMetadataDescriptor.sol/OpenFundRedemptionMetadataDescriptor.json');
const OpenFundRedemptionDelegateBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-Redemptions/OpenFundRedemptionDelegate.sol/OpenFundRedemptionDelegate.json');
const OpenFundRedemptionConcreteBin = require('@solvprotocol/contracts-v3-sft-open-fund/artifacts/contracts/open-fund-Redemptions/OpenFundRedemptionConcrete.sol/OpenFundRedemptionConcrete.json');
const sendCompile = require("../../../../commons/test-base/utils/sendCompile.js");

async function deployProxyAdmin(deployer) {
  const proxyAdminFactory = ethers.ContractFactory.fromSolidity(ProxyAdminBin, deployer);
  const proxyAdmin = await proxyAdminFactory.deploy();
  await proxyAdmin.deployed();
  // console.log(`ProxyAdmin deployed at: ${colors.green(proxyAdmin.address)}`);
  return proxyAdmin;
}

async function deployContractAsProxy(deployer, proxyAdmin, contractBin, initParams) {
  const contractFactory = ethers.ContractFactory.fromSolidity(contractBin, deployer);
  const contractImpl = await contractFactory.deploy();
  await contractImpl.deployed();

  const ProxyFactory = ethers.ContractFactory.fromSolidity(TransparentUpgradeableProxyBin, deployer);
  const initData = contractFactory.interface.encodeFunctionData('initialize', initParams);
  const proxy = await ProxyFactory.deploy(contractImpl.address, proxyAdmin.address, initData);
  return contractFactory.attach(proxy.address);
}

async function deployERC20(deployer, name, symbol, decimals, totalSupply) {
  const erc20MockFactory = ethers.ContractFactory.fromSolidity(ERC20MockBin, deployer);
  const erc20 = await erc20MockFactory.deploy(name, symbol, decimals, totalSupply);
  await erc20.deployed();
  // console.log(`${symbol} deployed at: ${colors.green(erc20.address)}`);
  return erc20;
}

async function deployAddressResolver(deployer, proxyAdmin, owner) {
  const addressResolver = await deployContractAsProxy(deployer, proxyAdmin, AddressResolverBin, [owner.address]);
  // console.log(`AddressResovler deployed at: ${colors.green(addressResolver.address)}`);
  return addressResolver;
}

async function deployOpenFundMarket(deployer, proxyAdmin, owner, addressResovler, currencies) {
  const navOracle = await deployContractAsProxy(deployer, proxyAdmin, NavOracleBin, [addressResovler.address]);
  // console.log(`NavOracle deployed at: ${colors.green(navOracle.address)}`);
  await addressResovler.connect(owner).importAddressesOnlyOwner([AddressResolverName.NAV_ORACLE], [navOracle.address]);

  const whitelistManager = await deployContractAsProxy(deployer, proxyAdmin, WhitelistStrategyManagerBin, [addressResovler.address]);
  // console.log(`WhitelistManager deployed at: ${colors.green(whitelistManager.address)}`);
  await addressResovler.connect(owner).importAddressesOnlyOwner([AddressResolverName.WHITELIST_MANAGER], [whitelistManager.address]);

  const openFundMarket = await deployContractAsProxy(deployer, proxyAdmin, OpenFundMarketBin, [addressResovler.address, owner.address]);
  // console.log(`OpenFundMarket deployed at: ${colors.green(openFundMarket.address)}`);
  await addressResovler.connect(owner).importAddressesOnlyOwner([AddressResolverName.OPEN_FUND_MARKET], [openFundMarket.address]);
  
  await openFundMarket.rebuildCache();
  await navOracle.rebuildCache();
  await whitelistManager.rebuildCache();

  for (let currency of currencies) {
    await openFundMarket.connect(owner).setCurrencyOnlyOwner(currency, true);
  }

  await openFundMarket.connect(owner).setProtocolFeeRateOnlyOwner(10);

  await sendCompile(path.join(__dirname, "../../../../markets/open-fund-market/artifacts/build-info/"), OpenFundMarketDBG.buildInfo)

  return [ navOracle, whitelistManager, openFundMarket ];
}

async function deploySVGBackgroundGenerator(deployer, proxyAdmin, owner, addressResolver, defaultSVGColorInfo = {strategyCount: 0, backgroundColor: '#41328E', patternColors: ['#5940DA', '#B86CF2']}) {
  const svgBackgroundGenerator = await deployContractAsProxy(deployer, proxyAdmin, SVGBackgroundGeneratorBin, [addressResolver.address, owner.address, defaultSVGColorInfo]);
  await svgBackgroundGenerator.rebuildCache();
  return svgBackgroundGenerator;
}

async function deployOpenFundShare(deployer, proxyAdmin, owner, addressResolver, svgBackgroundGenerator, name, symbol, decimals, allowRepayWithBalance = false, currencies = []) {
  const shareSVGFactory = ethers.ContractFactory.fromSolidity(DefaultOpenFundShareSVGBin, deployer);
  const shareSVG = await shareSVGFactory.deploy();
  // console.log(`OpenFundShareSVG deployed at: ${colors.green(shareSVG.address)}`);
  await shareSVG.initialize(addressResolver.address, svgBackgroundGenerator.address, owner.address);
  await shareSVG.rebuildCache();

  const shareDescriptor = await deployContractAsProxy(deployer, proxyAdmin, OpenFundShareMetadataDescriptorBin, [owner.address, shareSVG.address]);
  // console.log(`OpenFundShareDescriptor deployed at: ${colors.green(shareDescriptor.address)}`);

  const shareConcrete = await deployContractAsProxy(deployer, proxyAdmin, OpenFundShareConcreteBin, []);
  // console.log(`OpenFundShareConcrete deployed at: ${colors.green(shareConcrete.address)}`);

  const shareDelegate = await deployContractAsProxy(deployer, proxyAdmin, OpenFundShareDelegateBin, [
    addressResolver.address, name, symbol, decimals, 
    shareConcrete.address, shareDescriptor.address, owner.address, allowRepayWithBalance
  ]);
  // console.log(`OpenFundShareDelegate deployed at: ${colors.green(shareDelegate.address)}`);

  await shareDelegate.rebuildCache();

  for (let currency of currencies) {
    await shareDelegate.connect(owner).setCurrencyOnlyOwner(currency, true);
  }

  await sendCompile(path.join(__dirname, "../../../../sft/payable/open-fund/artifacts/build-info/"), OpenFundShareDelegateDBG.buildInfo)

  return [ shareSVG, shareDescriptor, shareConcrete, shareDelegate ];
}

async function deployOpenFundRedemption(deployer, proxyAdmin, owner, addressResolver, svgBackgroundGenerator, name, symbol, decimals, allowRepayWithBalance = false) {
  const redemptionSVGFactory = ethers.ContractFactory.fromSolidity(DefaultOpenFundRedemptionSVGBin, deployer);
  const redemptionSVG = await redemptionSVGFactory.deploy();
  // console.log(`OpenFundRedemptionSVG deployed at: ${colors.green(redemptionSVG.address)}`);
  await redemptionSVG.initialize(addressResolver.address, svgBackgroundGenerator.address, owner.address);
  await redemptionSVG.rebuildCache();

  const redemptionDescriptor = await deployContractAsProxy(deployer, proxyAdmin, OpenFundRedemptionMetadataDescriptorBin, [owner.address, redemptionSVG.address]);
  // console.log(`OpenFundRedemptionDescriptor deployed at: ${colors.green(redemptionDescriptor.address)}`);

  const redemptionConcrete = await deployContractAsProxy(deployer, proxyAdmin, OpenFundRedemptionConcreteBin, []);
  // console.log(`OpenFundRedemptionConcrete deployed at: ${colors.green(redemptionConcrete.address)}`);

  const redemptionDelegate = await deployContractAsProxy(deployer, proxyAdmin, OpenFundRedemptionDelegateBin, [
    addressResolver.address, name, symbol, decimals, 
    redemptionConcrete.address, redemptionDescriptor.address, owner.address, allowRepayWithBalance
  ]);
  // console.log(`OpenFundRedemptionDelegate deployed at: ${colors.green(redemptionDelegate.address)}`);

  await redemptionDelegate.rebuildCache();

  return [ redemptionSVG, redemptionDescriptor, redemptionConcrete, redemptionDelegate ];
}

module.exports = {
  deployProxyAdmin,
  deployERC20,
  deployAddressResolver,
  deployOpenFundMarket,
  deploySVGBackgroundGenerator,
  deployOpenFundShare,
  deployOpenFundRedemption
};