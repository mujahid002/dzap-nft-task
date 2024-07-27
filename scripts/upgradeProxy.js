const { ethers, upgrades } = require("hardhat");

const PROXY = "";

async function main() {
  const DZapStakingV2 = await hre.ethers.getContractFactory("DZapStaking");
  console.log("Upgrading DZapStaking...");
  await upgrades.upgradeProxy(PROXY, DZapStakingV2);
  console.log("DZapStaking upgraded successfully");
}

main();
