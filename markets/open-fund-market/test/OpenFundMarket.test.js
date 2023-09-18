const { ethers } = require('hardhat');
const { expect } = require('chai');
const { BigNumber} = require('@ethersproject/bignumber');

const contractDeploy = require('./lib/contractDeploy.js');
const BlockHelper = require('./lib/BlockHelper');

describe('Open-end Fund Market Test', () => {
  beforeEach(async function () {
    [ 
      this.deployer, this.owner, this.issuer, this.carryCollector, this.subscribeNavManager, this.redeemNavManager, 
      this.vault, this.buyer1, this.buyer2, this.buyer3, this.buyer4, this.others
    ] = await ethers.getSigners();

    this.USDT = await contractDeploy.deployERC20(this.deployer, 'Test USDT', 'USDT', 6, ethers.utils.parseUnits('10000000000', 6));
    this.USDC = await contractDeploy.deployERC20(this.deployer, 'Test USDC', 'USDC', 6, ethers.utils.parseUnits('10000000000', 6));
    this.SOLV = await contractDeploy.deployERC20(this.deployer, 'Solv Protocol', 'SOLV', 18, ethers.utils.parseUnits('10000000000', 18));

    await this.USDT.mint(this.issuer.address, ethers.utils.parseUnits('10000000000', 6));
    await this.USDT.mint(this.buyer1.address, ethers.utils.parseUnits('100000', 6));
    await this.USDT.mint(this.buyer2.address, ethers.utils.parseUnits('100000', 6));
    await this.USDT.mint(this.buyer3.address, ethers.utils.parseUnits('100000', 6));
    await this.USDT.mint(this.buyer4.address, ethers.utils.parseUnits('100000', 6));

    this.proxyAdmin = await contractDeploy.deployProxyAdmin(this.deployer);
    this.resolver = await contractDeploy.deployAddressResolver(this.deployer, this.proxyAdmin, this.owner);
    [ this.navOracle, this.whitelistManager, this.market ] = await contractDeploy.deployOpenFundMarket(this.deployer, this.proxyAdmin, this.owner, this.resolver, [this.USDT.address]);
    this.svgBackgroundGenerator = await contractDeploy.deploySVGBackgroundGenerator(this.deployer, this.proxyAdmin, this.owner, this.resolver);
    [ this.shareSVG, this.shareDescriptor, this.shareConcrete, this.shareDelegate ] = await contractDeploy.deployOpenFundShare(
      this.deployer, this.proxyAdmin, this.owner, this.resolver, this.svgBackgroundGenerator, 'General Open-end Fund Share', 'GOEFS', 18, false, [this.USDT.address]
    );
    [ this.redemptionSVG, this.redemptionDescriptor, this.redemptionConcrete, this.redemptionDelegate ] = await contractDeploy.deployOpenFundRedemption(
      this.deployer, this.proxyAdmin, this.owner, this.resolver, this.svgBackgroundGenerator, 'General Open-end Fund Redemption', 'GOEFR', 18, false
    );

    await this.market.connect(this.owner).addSFTOnlyOwner(this.shareDelegate.address, ethers.constants.AddressZero);
    await this.market.connect(this.owner).addSFTOnlyOwner(this.redemptionDelegate.address, ethers.constants.AddressZero);

    await this.market.connect(this.owner).setProtocolFeeRateOnlyOwner(0);
    await this.market.connect(this.owner).setProtocolFeeCollectorOnlyOwner(this.carryCollector.address);
  });
  
  it('test full process', async function () {
    const today = Math.floor((await ethers.provider.getBlock()).timestamp / 86400) * 86400;
    const createPoolTx = await this.market.connect(this.issuer).createPool([
      this.shareDelegate.address, this.redemptionDelegate.address, this.USDT.address, 100, this.vault.address, 
      today + 86400 * 10, this.carryCollector.address, this.subscribeNavManager.address, this.redeemNavManager.address, 
      this.navOracle.address, today, [], 
      [ ethers.utils.parseUnits('10000000', 6), 0, ethers.utils.parseUnits('10000000', 6), today, today + 86400 * 360 ]
    ]);

    const createPoolReceipt = await createPoolTx.wait();
    const poolId = createPoolReceipt.events.find(e => e.event === 'CreatePool').args.poolId;

    const subscribeAmount = ethers.utils.parseUnits('10000', 6);
    const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
    await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000000', 6));
    const subscribeTx = await this.market.connect(this.buyer1).subscribe(poolId, subscribeAmount, 0, expireTime);
    const subscribeReceipt = await subscribeTx.wait();
    const subscribeEvent = subscribeReceipt.events.find(e => e.event === 'Subscribe');
    const shareId = subscribeEvent.args.tokenId;
    const shareValue = subscribeEvent.args.value;

    await BlockHelper.advanceToTimeAndBlock(today + 86400 * 10 + 1);
    await this.shareDelegate.connect(this.buyer1)['approve(address,uint256)'](this.market.address, shareId);
    const redeemValue = shareValue;
    const redeemTx = await this.market.connect(this.buyer1).requestRedeem(poolId, shareId, 0, redeemValue);
    const redeemReceipt = await redeemTx.wait();
    const redeemEvent = redeemReceipt.events.find(e => e.event === 'RequestRedeem');
    const redemptionId = redeemEvent.args.openFundRedemptionId;
    const redeemSlot = await this.redemptionDelegate.slotOf(redemptionId);

    // await this.redemptionDelegate.connect(this.buyer1)['approve(address,uint256)'](this.market.address, redemptionId);
    // const revokeTx = await this.market.connect(this.buyer1).revokeRedeem(poolId, redemptionId);
    // const revokeReceipt = await revokeTx.wait();
    // const revokeEvent = revokeReceipt.events.find(e => e.event === 'RevokeRedeem');
    // const shareIdAfterRevoke = revokeEvent.args.openFundShareId;

    await BlockHelper.advanceToTimeAndBlock(today + 86400 * 11);
    const closeRedeemSlotTx = await this.market.connect(this.issuer).closeCurrentRedeemSlot(poolId);
    const closeRedeemSlotReceipt = await closeRedeemSlotTx.wait();
    const closeRedeemSlotEvent = closeRedeemSlotReceipt.events.find(e => e.event === 'CloseRedeemSlot');
    // console.log(closeRedeemSlotEvent.args);

    const redeemNav = ethers.utils.parseUnits('1.05', 6);
    const currencyBalance = ethers.utils.parseUnits('10050', 6);
    const setRedeemNavTx = await this.market.connect(this.redeemNavManager).setRedeemNav(poolId, redeemSlot, redeemNav, currencyBalance);
    const setRedeemNavReceipt = await setRedeemNavTx.wait();
    const setRedeemNavEvent = setRedeemNavReceipt.events.find(e => e.event === 'SetRedeemNav').args;
    // console.log(setRedeemNavEvent);

    const redeemInfo = await this.redemptionConcrete.getRedeemInfo(redeemSlot);
    // console.log(redeemInfo);

    const repayAmount = redeemValue.mul(setRedeemNavEvent.nav).div(BigNumber.from('10').pow(await this.redemptionDelegate.valueDecimals()));
    await this.USDT.connect(this.issuer).approve(this.redemptionDelegate.address, repayAmount);
    await this.redemptionDelegate.connect(this.issuer).repay(redeemSlot, this.USDT.address, repayAmount);

    // const repayInfo = await this.redemptionConcrete.slotRepayInfo(redeemSlot);
    // console.log(repayInfo);

    const usdtBalanceBeforeClaim = await this.USDT.balanceOf(this.buyer1.address);
    const claimTx = await this.redemptionDelegate.connect(this.buyer1).claimTo(this.buyer1.address, redemptionId, this.USDT.address, redeemValue);
    const claimReceipt = await claimTx.wait();
    const claimEvent = claimReceipt.events.find(e => e.event === 'Claim').args;
    const usdtBalanceAfterClaim = await this.USDT.balanceOf(this.buyer1.address);
    expect(claimEvent.claimCurrencyAmount).to.be.equal(usdtBalanceAfterClaim.sub(usdtBalanceBeforeClaim));
    expect(claimEvent.claimCurrencyAmount).to.be.equal(redeemValue.mul(setRedeemNavEvent.nav).div(ethers.utils.parseUnits('1', 18)));
  });

  it('test full process plus', async function () {
    const today = Math.floor((await ethers.provider.getBlock()).timestamp / 86400) * 86400;
    const createPoolTx = await this.market.connect(this.issuer).createPool([
      this.shareDelegate.address, this.redemptionDelegate.address, this.USDT.address, 100, this.vault.address, 
      today + 86400 * 10, this.carryCollector.address, this.subscribeNavManager.address, this.redeemNavManager.address, 
      this.navOracle.address, today, [], 
      [ ethers.utils.parseUnits('10000000', 6), 0, ethers.utils.parseUnits('10000000', 6), today, today + 86400 * 360 ]
    ]);

    const createPoolReceipt = await createPoolTx.wait();
    const poolId = createPoolReceipt.events.find(e => e.event === 'CreatePool').args.poolId;

    const subscribeAmount1 = ethers.utils.parseUnits('10000', 6);
    await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000000', 6));
    const subscribeTx1 = await this.market.connect(this.buyer1).subscribe(poolId, subscribeAmount1, 0, (await ethers.provider.getBlock()).timestamp + 300);
    const shareId1 = (await subscribeTx1.wait()).events.find(e => e.event === 'Subscribe').args.tokenId;
    expect(ethers.utils.formatUnits(await this.shareDelegate['balanceOf(uint256)'](shareId1), 18)).to.be.equal(ethers.utils.formatUnits(subscribeAmount1, 6));

    // after value date 
    await BlockHelper.advanceToTimeAndBlock(today + 86400 * 11);
    const subscribeAmount2 = ethers.utils.parseUnits('50000', 6);
    await this.USDT.connect(this.buyer2).approve(this.market.address, ethers.utils.parseUnits('10000000000', 6));
    const subscribeTx2 = await this.market.connect(this.buyer2).subscribe(poolId, subscribeAmount2, 0, (await ethers.provider.getBlock()).timestamp + 300);
    const shareId2 = (await subscribeTx2.wait()).events.find(e => e.event === 'Subscribe').args.tokenId;
    expect(ethers.utils.formatUnits(await this.shareDelegate['balanceOf(uint256)'](shareId2), 18)).to.be.equal(ethers.utils.formatUnits(subscribeAmount2, 6));
  
    // after subscribe nav set
    await this.market.connect(this.subscribeNavManager).setSubscribeNav(poolId, (await ethers.provider.getBlock()).timestamp, ethers.utils.parseUnits('1.005', 6));
    const subscribeAmount3 = ethers.utils.parseUnits('20100', 6);
    await this.USDT.connect(this.buyer3).approve(this.market.address, ethers.utils.parseUnits('10000000000', 6));
    const subscribeTx3 = await this.market.connect(this.buyer3).subscribe(poolId, subscribeAmount3, 0, (await ethers.provider.getBlock()).timestamp + 300);
    const shareId3 = (await subscribeTx3.wait()).events.find(e => e.event === 'Subscribe').args.tokenId;
    expect(await this.shareDelegate['balanceOf(uint256)'](shareId3)).to.be.equal(subscribeAmount3.div(ethers.utils.parseUnits('1.005', 6)).mul(ethers.utils.parseUnits('1', 18)));
  
    // request redeem
    await BlockHelper.advanceToTimeAndBlock(today + 86400 * 12);
    await this.shareDelegate.connect(this.buyer1)['approve(address,uint256)'](this.market.address, shareId1);
    const redeemValue1 = await this.shareDelegate['balanceOf(uint256)'](shareId1);
    const redeemTx1 = await this.market.connect(this.buyer1).requestRedeem(poolId, shareId1, 0, redeemValue1);
    const redemptionId1 = (await redeemTx1.wait()).events.find(e => e.event === 'RequestRedeem').args.openFundRedemptionId;
    const redeemSlot1 = await this.redemptionDelegate.slotOf(redemptionId1);
    expect(await this.redemptionDelegate['balanceOf(uint256)'](redemptionId1)).to.be.equal(redeemValue1);

    await this.shareDelegate.connect(this.buyer2)['approve(address,uint256)'](this.market.address, shareId2);
    const shareValue2 = await this.shareDelegate['balanceOf(uint256)'](shareId2);
    const redeemValue2 = shareValue2.div(2);
    const redeemTx2 = await this.market.connect(this.buyer2).requestRedeem(poolId, shareId2, 0, redeemValue2);
    const redemptionId2 = (await redeemTx2.wait()).events.find(e => e.event === 'RequestRedeem').args.openFundRedemptionId;
    expect(await this.shareDelegate['balanceOf(uint256)'](shareId2)).to.be.equal(shareValue2.sub(redeemValue2));
    expect(await this.redemptionDelegate['balanceOf(uint256)'](redemptionId2)).to.be.equal(redeemValue2);

    await this.redemptionDelegate.connect(this.buyer2)['approve(address,uint256)'](this.market.address, redemptionId2);
    const revokeTx2 = await this.market.connect(this.buyer2).revokeRedeem(poolId, redemptionId2);
    const shareIdAfterRevoke2 = (await revokeTx2.wait()).events.find(e => e.event === 'RevokeRedeem').args.openFundShareId;
    await expect(this.redemptionDelegate['balanceOf(uint256)'](redemptionId2)).to.be.revertedWith('ERC3525: invalid token ID');
    expect(await this.shareDelegate['balanceOf(uint256)'](shareIdAfterRevoke2)).to.be.equal(redeemValue2);

    await BlockHelper.advanceToTimeAndBlock(today + 86400 * 15);
    await this.market.connect(this.subscribeNavManager).setSubscribeNav(poolId, (await ethers.provider.getBlock()).timestamp, ethers.utils.parseUnits('1.02', 6));
    await this.market.connect(this.issuer).closeCurrentRedeemSlot(poolId);

    const redeemNav1 = ethers.utils.parseUnits('1.02', 6);
    const currencyBalance1 = ethers.utils.parseUnits('81600', 6);
    const setRedeemNavTx1 = await this.market.connect(this.redeemNavManager).setRedeemNav(poolId, redeemSlot1, redeemNav1, currencyBalance1);
    const setRedeemNavReceipt1 = await setRedeemNavTx1.wait();
    const settleCarryEvent1 = setRedeemNavReceipt1.events.find(e => e.event === 'SettleCarry').args;
    const setRedeemNavEvent1 = setRedeemNavReceipt1.events.find(e => e.event === 'SetRedeemNav').args;
    expect(settleCarryEvent1.carryAmount).to.be.equal(ethers.utils.parseUnits('16', 6));
    expect(setRedeemNavEvent1.nav).to.be.equal(ethers.utils.parseUnits('1.0198', 6));

    const repayAmount1 = redeemValue1.mul(setRedeemNavEvent1.nav).div(ethers.utils.parseUnits('1', 18));
    await this.USDT.connect(this.issuer).approve(this.redemptionDelegate.address, repayAmount1);
    await this.redemptionDelegate.connect(this.issuer).repay(redeemSlot1, this.USDT.address, repayAmount1);

    expect(await this.redemptionConcrete.getRedeemNav(redeemSlot1)).to.be.equal(ethers.utils.parseUnits('1.0198', 6));
    const claimValue1 = redeemValue1.div(2);
    const usdtBalanceBeforeClaim1 = await this.USDT.balanceOf(this.buyer1.address);
    const claimTx1 = await this.redemptionDelegate.connect(this.buyer1).claimTo(this.buyer1.address, redemptionId1, this.USDT.address, claimValue1);
    const claimReceipt1 = await claimTx1.wait();
    const claimEvent1 = claimReceipt1.events.find(e => e.event === 'Claim').args;
    const usdtBalanceAfterClaim1 = await this.USDT.balanceOf(this.buyer1.address);
    expect(usdtBalanceAfterClaim1.sub(usdtBalanceBeforeClaim1)).to.be.equal(claimValue1.mul(setRedeemNavEvent1.nav).div(ethers.utils.parseUnits('1', 18)));
  
    // subscription & redeem round 2
    await BlockHelper.advanceToTimeAndBlock(today + 86400 * 16);
    await this.USDT.connect(this.buyer4).approve(this.market.address, ethers.utils.parseUnits('10000000000', 6));
    const subscribeAmount4 = ethers.utils.parseUnits('20396', 6);
    const subscribeTx4 = await this.market.connect(this.buyer4).subscribe(poolId, subscribeAmount4, 0, (await ethers.provider.getBlock()).timestamp + 300);
    const shareId4 = (await subscribeTx4.wait()).events.find(e => e.event === 'Subscribe').args.tokenId;
    const expectValue4 = subscribeAmount4.mul(ethers.utils.parseUnits('1', 18)).div(setRedeemNavEvent1.nav);
    expect(await this.shareDelegate['balanceOf(uint256)'](shareId4)).to.be.equal(expectValue4);

    await BlockHelper.advanceToTimeAndBlock(today + 86400 * 20);
    await this.shareDelegate.connect(this.buyer3)['approve(address,uint256)'](this.market.address, shareId3);
    const redeemValue3 = await this.shareDelegate['balanceOf(uint256)'](shareId3);
    const redeemTx3 = await this.market.connect(this.buyer3).requestRedeem(poolId, shareId3, 0, redeemValue3);
    const redemptionId3 = (await redeemTx3.wait()).events.find(e => e.event === 'RequestRedeem').args.openFundRedemptionId;
    const redeemSlot3 = await this.redemptionDelegate.slotOf(redemptionId3);
    expect(await this.redemptionDelegate['balanceOf(uint256)'](redemptionId3)).to.be.equal(redeemValue3);

    await this.shareDelegate.connect(this.buyer4)['approve(address,uint256)'](this.market.address, shareId4);
    const redeemValue4 = (await this.shareDelegate['balanceOf(uint256)'](shareId4)).div(2);
    const redeemTx4 = await this.market.connect(this.buyer4).requestRedeem(poolId, shareId4, 0, redeemValue4);
    const redemptionId4 = (await redeemTx4.wait()).events.find(e => e.event === 'RequestRedeem').args.openFundRedemptionId;
    const redeemSlot4 = await this.redemptionDelegate.slotOf(redemptionId4);
    expect(await this.redemptionDelegate['balanceOf(uint256)'](redemptionId4)).to.be.equal(redeemValue4);
    expect(redeemSlot4).to.be.equal(redeemSlot3);

    await this.market.connect(this.issuer).closeCurrentRedeemSlot(poolId);
    const redeemNav2 = ethers.utils.parseUnits('1.05', 6);
    const currencyBalance2 = ethers.utils.parseUnits('94500', 6);
    const setRedeemNavTx2 = await this.market.connect(this.redeemNavManager).setRedeemNav(poolId, redeemSlot4, redeemNav2, currencyBalance2);
    const setRedeemNavReceipt2 = await setRedeemNavTx2.wait();
    const settleCarryEvent2 = setRedeemNavReceipt2.events.find(e => e.event === 'SettleCarry').args;
    const setRedeemNavEvent2 = setRedeemNavReceipt2.events.find(e => e.event === 'SetRedeemNav').args;
    expect(settleCarryEvent2.carryAmount).to.be.equal(ethers.utils.parseUnits('27', 6));
    expect(setRedeemNavEvent2.nav).to.be.equal(ethers.utils.parseUnits('1.0497', 6));

    const repayAmount2 = redeemValue3.add(redeemValue4).mul(setRedeemNavEvent2.nav).div(ethers.utils.parseUnits('1', 18));
    await this.USDT.connect(this.issuer).approve(this.redemptionDelegate.address, repayAmount2);
    await this.redemptionDelegate.connect(this.issuer).repay(redeemSlot4, this.USDT.address, repayAmount2);

    const usdtBalanceBeforeClaim4 = await this.USDT.balanceOf(this.buyer4.address);
    const claimTx4 = await this.redemptionDelegate.connect(this.buyer4).claimTo(this.buyer4.address, redemptionId4, this.USDT.address, redeemValue4);
    const claimReceipt4 = await claimTx4.wait();
    const claimEvent4 = claimReceipt4.events.find(e => e.event === 'Claim').args;
    const usdtBalanceAfterClaim4 = await this.USDT.balanceOf(this.buyer4.address);
    expect(usdtBalanceAfterClaim4.sub(usdtBalanceBeforeClaim4)).to.be.equal(redeemValue4.mul(setRedeemNavEvent2.nav).div(ethers.utils.parseUnits('1', 18)));
  });

  describe('create pool test', function () {
    beforeEach(async function () {
      this.today = Math.floor((await ethers.provider.getBlock()).timestamp / 86400) * 86400;
      this.defaultInputPoolInfo = [
        this.shareDelegate.address, this.redemptionDelegate.address, this.USDT.address, 100, this.vault.address, 
        this.today + 86400 * 10, this.carryCollector.address, this.subscribeNavManager.address, this.redeemNavManager.address, 
        this.navOracle.address, this.today, [], 
        [ ethers.utils.parseUnits('10000000', 6), 0, ethers.utils.parseUnits('10000000', 6), this.today, this.today + 86400 * 360 ]
      ];
    });

    context('validate status when pool created', function () {
      it('validate events', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const createPoolReceipt = await createPoolTx.wait();
        const createPoolEvent = createPoolReceipt.events.find(e => e.event === 'CreatePool');
        const setSubscribeNavEvent = createPoolReceipt.events.find(e => e.event === 'SetSubscribeNav');

        const expectedPoolId = ethers.utils.keccak256(
          ethers.utils.AbiCoder.prototype.encode(["tuple(address,uint256)"],
          [[this.shareDelegate.address, await this.shareDelegate.slotByIndex(0)]])
        );
        expect(createPoolEvent.args.poolId).to.be.equal(expectedPoolId);
        expect(createPoolEvent.args.currency).to.be.equal(this.USDT.address);
        expect(createPoolEvent.args.sft).to.be.equal(this.shareDelegate.address);

        expect(setSubscribeNavEvent.args.poolId).to.be.equal(expectedPoolId);
        expect(setSubscribeNavEvent.args.nav).to.be.equal(ethers.utils.parseUnits('1.0', 6));
      });

      it('validate pool info', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const createPoolEvent = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool');
        const poolId = createPoolEvent.args.poolId;
        const poolInfo = await this.market.poolInfos(poolId);

        expect(poolInfo.poolSFTInfo.openFundShare).to.be.equal(this.shareDelegate.address);
        expect(poolInfo.poolSFTInfo.openFundRedemption).to.be.equal(this.redemptionDelegate.address);
        expect(poolInfo.poolSFTInfo.openFundShareSlot).to.be.equal(await this.shareDelegate.slotByIndex(0));
        expect(poolInfo.poolSFTInfo.latestRedeemSlot).to.be.equal(0);
        expect(poolInfo.poolFeeInfo.carryRate).to.be.equal(this.defaultInputPoolInfo[3]);
        expect(poolInfo.poolFeeInfo.carryCollector).to.be.equal(this.carryCollector.address);
        expect(poolInfo.poolFeeInfo.latestProtocolFeeSettleTime).to.be.equal(this.defaultInputPoolInfo[5]);
        expect(poolInfo.managerInfo.poolManager).to.be.equal(this.issuer.address);
        expect(poolInfo.managerInfo.subscribeNavManager).to.be.equal(this.subscribeNavManager.address);
        expect(poolInfo.managerInfo.redeemNavManager).to.be.equal(this.redeemNavManager.address);
        expect(poolInfo.subscribeLimitInfo.hardCap).to.be.equal(this.defaultInputPoolInfo[12][0]);
        expect(poolInfo.subscribeLimitInfo.subscribeMin).to.be.equal(this.defaultInputPoolInfo[12][1]);
        expect(poolInfo.subscribeLimitInfo.subscribeMax).to.be.equal(this.defaultInputPoolInfo[12][2]);
        expect(poolInfo.subscribeLimitInfo.fundraisingStartTime).to.be.equal(this.defaultInputPoolInfo[12][3]);
        expect(poolInfo.subscribeLimitInfo.fundraisingEndTime).to.be.equal(this.defaultInputPoolInfo[12][4]);
        expect(poolInfo.vault).to.be.equal(this.vault.address);
        expect(poolInfo.currency).to.be.equal(this.USDT.address);
        expect(poolInfo.navOracle).to.be.equal(this.navOracle.address);
        expect(poolInfo.valueDate).to.be.equal(this.defaultInputPoolInfo[5]);
        expect(poolInfo.permissionless).to.be.equal(this.defaultInputPoolInfo[11].length == 0);
        expect(poolInfo.fundraisingAmount).to.be.equal(0);
      });

      it('validate OpenFundShare status', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const createPoolEvent = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool');

        const poolId = createPoolEvent.args.poolId;
        const poolInfo = await this.market.poolInfos(poolId);
        const shareSlot = poolInfo.poolSFTInfo.openFundShareSlot;

        const slotBaseInfo = await this.shareConcrete.slotBaseInfo(shareSlot);
        const slotExtInfo = await this.shareConcrete.slotExtInfo(shareSlot);

        expect(slotBaseInfo.issuer).to.be.equal(this.issuer.address);
        expect(slotBaseInfo.currency).to.be.equal(this.USDT.address);
        expect(slotBaseInfo.valueDate).to.be.equal(this.defaultInputPoolInfo[5]);
        expect(slotBaseInfo.maturity).to.be.equal(this.defaultInputPoolInfo[12][4]);
        expect(slotBaseInfo.createTime).to.be.equal(this.defaultInputPoolInfo[10]);
        expect(slotBaseInfo.transferable).to.be.true;
        expect(slotBaseInfo.isValid).to.be.true;

        expect(slotExtInfo.supervisor).to.be.equal(this.redeemNavManager.address);
        expect(slotExtInfo.issueQuota).to.be.equal(ethers.constants.MaxUint256);
        expect(slotExtInfo.interestType).to.be.equal(1);
        expect(slotExtInfo.interestRate).to.be.equal(0);
        expect(slotExtInfo.isInterestRateSet).to.be.false;
      });

      it('validate nav oracle status', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const createPoolEvent = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool');

        const poolId = createPoolEvent.args.poolId;
        const poolInfo = await this.market.poolInfos(poolId);

        const [ subscribeNav, subscribeNavTime ] = await this.navOracle.getSubscribeNav(poolId, this.today + 100);
        expect(subscribeNav).to.be.equal(ethers.utils.parseUnits('1', 6));
        expect(subscribeNavTime).to.be.equal(this.today);

        const allTimeHighRedeemNav = await this.navOracle.getAllTimeHighRedeemNav(poolId);
        expect(allTimeHighRedeemNav).to.be.equal(ethers.utils.parseUnits('1', 6));
      });
    });

    context('create pool in invalid conditions should fail', function () {
      it('create pool with invalid currency', async function () {
        this.defaultInputPoolInfo[2] = this.USDC.address;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: currency not allowed');
      });

      it('create pool with invalid OpenFundShare', async function () {
        const [ , , , shareDelegate ] = await contractDeploy.deployOpenFundShare(
          this.deployer, this.proxyAdmin, this.owner, this.resolver, 'General Open-end Fund Share', 'GOEFS', 18, false, [this.USDT.address]
        );
        this.defaultInputPoolInfo[0] = shareDelegate.address;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: share not allowed');
      });

      it('create pool with invalid OpenFundRedemption', async function () {
        const [ , , , redemptionDelegate ] = await contractDeploy.deployOpenFundRedemption(
          this.deployer, this.proxyAdmin, this.owner, this.resolver, 'General Open-end Fund Redemption', 'GOEFR', 18, false
        );
        this.defaultInputPoolInfo[1] = redemptionDelegate.address;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: redemption not allowed');
      });

      it('create pool by invalid OpenFundShare manager', async function () {
        const [ , , , shareDelegate ] = await contractDeploy.deployOpenFundShare(
          this.deployer, this.proxyAdmin, this.owner, this.resolver, 'General Open-end Fund Share', 'GOEFS', 18, false, [this.USDT.address]
        );
        const [ , , , redemptionDelegate ] = await contractDeploy.deployOpenFundRedemption(
          this.deployer, this.proxyAdmin, this.owner, this.resolver, 'General Open-end Fund Redemption', 'GOEFR', 18, false
        );
        await this.market.connect(this.owner).addSFTOnlyOwner(shareDelegate.address, this.others.address);
        await this.market.connect(this.owner).addSFTOnlyOwner(redemptionDelegate.address, this.issuer.address);
        this.defaultInputPoolInfo[0] = shareDelegate.address;
        this.defaultInputPoolInfo[1] = redemptionDelegate.address;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid share manager');
      });

      it('create pool by invalid OpenFundRedemption manager', async function () {
        const [ , , , shareDelegate ] = await contractDeploy.deployOpenFundShare(
          this.deployer, this.proxyAdmin, this.owner, this.resolver, 'General Open-end Fund Share', 'GOEFS', 18, false, [this.USDT.address]
        );
        const [ , , , redemptionDelegate ] = await contractDeploy.deployOpenFundRedemption(
          this.deployer, this.proxyAdmin, this.owner, this.resolver, 'General Open-end Fund Redemption', 'GOEFR', 18, false
        );
        await this.market.connect(this.owner).addSFTOnlyOwner(shareDelegate.address, this.issuer.address);
        await this.market.connect(this.owner).addSFTOnlyOwner(redemptionDelegate.address, this.others.address);
        this.defaultInputPoolInfo[0] = shareDelegate.address;
        this.defaultInputPoolInfo[1] = redemptionDelegate.address;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid redemption manager');
      });

      it('create pool with invalid min & max value', async function () {
        this.defaultInputPoolInfo[12][1] = ethers.utils.parseUnits('10000001', 6);
        this.defaultInputPoolInfo[12][2] = ethers.utils.parseUnits('10000000', 6);
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid min and max');
      });

      it('create pool when valueDate < fundraisingStartTime', async function () {
        this.defaultInputPoolInfo[12][3] = this.defaultInputPoolInfo[5] + 1;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid valueDate');
      });

      it('create pool when fundraisingStartTime > fundraisingEndTime', async function () {
        this.defaultInputPoolInfo[12][4] = this.defaultInputPoolInfo[12][3] - 1;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid startTime and endTime');
      });

      it('create pool when fundraisingEndTime < currentBlockTime', async function () {
        this.defaultInputPoolInfo[12][3] = (await ethers.provider.getBlock()).timestamp;
        this.defaultInputPoolInfo[12][4] = (await ethers.provider.getBlock()).timestamp;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid endTime');
      });

      it('create pool when valueDate < currentBlockTime', async function () {
        this.defaultInputPoolInfo[5] = (await ethers.provider.getBlock()).timestamp;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('EarnConcrete: invalid valueDate');
      });

      it('create pool when fundraisingEndTime < valueDate', async function () {
        this.defaultInputPoolInfo[12][4] = this.defaultInputPoolInfo[5] - 1;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('EarnConcrete: invalid maturity');
      });

      it('create pool when vault address == 0', async function () {
        this.defaultInputPoolInfo[4] = ethers.constants.AddressZero;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid vault');
      });

      it('create pool when vault carry collector == 0', async function () {
        this.defaultInputPoolInfo[6] = ethers.constants.AddressZero;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid carryCollector');
      });

      it('create pool when vault subscribe nav manager  == 0', async function () {
        this.defaultInputPoolInfo[7] = ethers.constants.AddressZero;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid subscribeNavManager');
      });

      it('create pool when vault redeem nav manager  == 0', async function () {
        this.defaultInputPoolInfo[8] = ethers.constants.AddressZero;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid redeemNavManager');
      });

      it('create pool when vault carry rate > 10000', async function () {
        this.defaultInputPoolInfo[3] = 10001;
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('OFM: invalid carryRate');
      });

      it('create pool when currency is not supported by OpenFundShare', async function () {
        await this.shareDelegate.connect(this.owner).setCurrencyOnlyOwner(this.USDT.address, false);
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('EarnConcrete: currency not allowed');
      });

      it('create pool when it already existed', async function () {
        await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        await expect(
          this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo)
        ).to.be.revertedWith('SFTIssuableDelegate: slot already exists');
      });
    });
  });

  describe('subscribe test', function () {
    beforeEach(async function () {
      this.today = Math.floor((await ethers.provider.getBlock()).timestamp / 86400) * 86400;
      this.defaultInputPoolInfo = [
        this.shareDelegate.address, this.redemptionDelegate.address, this.USDT.address, 100, this.vault.address, 
        this.today + 86400 * 10, this.carryCollector.address, this.subscribeNavManager.address, this.redeemNavManager.address, 
        this.navOracle.address, this.today, [], 
        [ ethers.utils.parseUnits('1000000', 6), 0, ethers.utils.parseUnits('1000000', 6), this.today, this.today + 86400 * 360 ]
      ];
    });

    context('validate status after subscription', function () {
      it('validate events', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;
        
        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const subscribeTx = await this.market.connect(this.buyer1).subscribe(poolId, ethers.utils.parseUnits('10000', 6), 0, this.today + 86400 * 360);
        const subscribeReceipt = await subscribeTx.wait();
        const subscribeEvent = subscribeReceipt.events.find(e => e.event === 'Subscribe');

        expect(subscribeEvent.args.poolId).to.equal(poolId);
        expect(subscribeEvent.args.buyer).to.equal(this.buyer1.address);
        expect(subscribeEvent.args.tokenId).to.equal(await this.shareDelegate.tokenOfOwnerByIndex(this.buyer1.address, 0));;
        expect(subscribeEvent.args.value).to.equal(ethers.utils.parseUnits('10000', 18));
        expect(subscribeEvent.args.currency).to.equal(this.USDT.address);
        expect(subscribeEvent.args.nav).to.equal(ethers.utils.parseUnits('1', 6));
        expect(subscribeEvent.args.payment).to.equal(ethers.utils.parseUnits('10000', 6));
      });
    });

    context('subscribe in invalid conditions should fail', function () {
      it('subscribe when transaction expired', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;
        
        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp - 1;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, ethers.utils.parseUnits('10000', 6), 0, expireTime)
        ).to.be.revertedWith('OFM: expired');
      });

      it('subscribe when not in whitelist of non-permissionless pool', async function () {
        this.defaultInputPoolInfo[11] = [ this.buyer1.address, this.buyer2.address ]; 
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;
        
        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer3).subscribe(poolId, ethers.utils.parseUnits('10000', 6), 0, expireTime)
        ).to.be.revertedWith('OFM: not in whitelist');
      });
      
      it('subscribe when fundraising not started', async function () {
        this.defaultInputPoolInfo[12][3] = (await ethers.provider.getBlock()).timestamp + 100;
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;
        
        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, ethers.utils.parseUnits('10000', 6), 0, expireTime)
        ).to.be.revertedWith('OFM: fundraising not started');
      });
      
      it('subscribe when fundraising ended', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;
        
        await BlockHelper.advanceToTimeAndBlock(this.defaultInputPoolInfo[12][4] + 1);
        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, ethers.utils.parseUnits('10000', 6), 0, expireTime)
        ).to.be.revertedWith('OFM: fundraising ended');
      });
      
      it('subscribe when fundraising hard cap reached before value date', async function () {
        this.defaultInputPoolInfo[12][0] = ethers.utils.parseUnits('10000', 6);
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await this.market.connect(this.buyer1).subscribe(poolId, this.defaultInputPoolInfo[12][0], 0, expireTime);
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, 1, 0, expireTime)
        ).to.be.revertedWith('OFM: hard cap reached');
      });
      
      it('subscribe when purchase amount < subscribe min limit', async function () {
        this.defaultInputPoolInfo[12][1] = ethers.utils.parseUnits('100', 6);
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, ethers.utils.parseUnits('99', 6), 0, expireTime)
        ).to.be.revertedWith('OFM: less than subscribe min limit');
      });
      
      it('subscribe when purchase amount > subscribe max limit', async function () {
        this.defaultInputPoolInfo[12][2] = ethers.utils.parseUnits('1000', 6);
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, ethers.utils.parseUnits('1001', 6), 0, expireTime)
        ).to.be.revertedWith('OFM: exceed subscribe max limit');
      });

      it('subscribe when currency balance not enough', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const currencyBalance = await this.USDT.balanceOf(this.buyer1.address);
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, currencyBalance.add(1), 0, expireTime)
        ).to.be.revertedWith('STF');
      });

      it('subscribe when currency allowance not enough', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        const currencyAmount = ethers.utils.parseUnits('1000', 6);
        await this.USDT.connect(this.buyer1).approve(this.market.address, currencyAmount - 1);
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, currencyAmount, 0, expireTime)
        ).to.be.revertedWith('STF');
      });

      it('subscribe when the given OpenFundShareId does not exist', async function () {
        const createPoolTx = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId = (await createPoolTx.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        await expect(
          this.market.connect(this.buyer1).subscribe(poolId, ethers.utils.parseUnits('1000', 6), 123, expireTime)
        ).to.be.revertedWith('ERC3525: invalid token ID');
      });

      it('subscribe when slot of the given OpenFundShareId does not match', async function () {
        const createPoolTx1 = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId1 = (await createPoolTx1.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        this.defaultInputPoolInfo[10] = this.today + 86400;
        const createPoolTx2 = await this.market.connect(this.issuer).createPool(this.defaultInputPoolInfo);
        const poolId2 = (await createPoolTx2.wait()).events.find(e => e.event === 'CreatePool').args.poolId;

        await this.USDT.connect(this.buyer1).approve(this.market.address, ethers.utils.parseUnits('10000000', 6));
        const expireTime = (await ethers.provider.getBlock()).timestamp + 300;
        const subscribeTx1 = await this.market.connect(this.buyer1).subscribe(poolId1, ethers.utils.parseUnits('1000', 6), 0, expireTime);
        const shareId1 = (await subscribeTx1.wait()).events.find(e => e.event === 'Subscribe').args.tokenId;

        await expect(
          this.market.connect(this.buyer1).subscribe(poolId2, ethers.utils.parseUnits('1000', 6), shareId1, expireTime)
        ).to.be.revertedWith('OFM: slot not match');
      });
    });
  });

})