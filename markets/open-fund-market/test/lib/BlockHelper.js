const { ethers } = require('hardhat');

const advanceTime = async (time) => {
  return ethers.provider.send("evm_increaseTime", [time])
}

const advanceBlock = async () => {
  return ethers.provider.send("evm_mine", [])
}

const advanceTimeAndBlock = async (time) => {
  const block = await ethers.provider.getBlock('latest')
  return ethers.provider.send("evm_mine", [block.timestamp + time])
}

const advanceToTimeAndBlock = async (time) => {
  return ethers.provider.send("evm_mine", [time])
}

module.exports = {
  advanceTime,
  advanceBlock,
  advanceTimeAndBlock,
  advanceToTimeAndBlock,
};