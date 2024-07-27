const { ethers, upgrades } = require("hardhat");

const PROXY = "0x91Ce856e9eFB78b57002Ff2E88C80b856F893138";

async function main() {
  const DZapStakingV2 = await hre.ethers.getContractFactory("DZapStaking");
  console.log("Upgrading DZapStaking...");
  await upgrades.upgradeProxy(PROXY, DZapStakingV2);
  console.log("DZapStaking upgraded successfully");
}

main();

// yarn hardhat run scripts/upgradeProxy.js --network polygonAmoy
