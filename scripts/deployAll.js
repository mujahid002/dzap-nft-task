const { ethers, run, upgrades } = require("hardhat");

async function main() {
  // DZapNfts
  const DZapNfts = await hre.ethers.getContractFactory("DZapNfts");
  console.log("Deploying DZapNfts Contract...");
  const dZapNfts = await DZapNfts.deploy({
    gasPrice: 30000000000,
  });
  await dZapNfts.waitForDeployment();
  const dZapNftsAddress = await dZapNfts.getAddress();
  console.log("DZapNfts Contract Address:", dZapNftsAddress);
  console.log("----------------------------------------------------------");

  // DZapStaking
  const DZapStaking = await hre.ethers.getContractFactory("DZapStaking");
  console.log("Deploying DZapStaking Contract...");
  const dZapStaking = await upgrades.deployProxy(
    DZapStaking,
    [stakingTokenContractAddress],
    {
      initializer: "initialize",
    }
  );
  await dZapStaking.deployed();
  const dZapStakingAddress = dZapStaking.address;
  console.log("DZapStaking Contract Address:", dZapStakingAddress);
  //   const DZapStaking = await hre.ethers.getContractFactory("DZapStaking");
  //   console.log("Deploying DZapStaking Contract...");
  //   const dZapStaking = await DZapStaking.deploy(dZapNftsAddress, {
  //     gasPrice: 33000000000,
  //   });
  //   await dZapStaking.waitForDeployment();
  //   const dZapStakingAddress = await dZapStaking.getAddress();
  //   console.log("DZapStaking Contract Address:", dZapStakingAddress);
  console.log("----------------------------------------------------------");

  // DZapRewardToken
  const DZapRewardToken = await hre.ethers.getContractFactory(
    "DZapRewardToken"
  );
  console.log("Deploying DZapRewardToken Contract...");
  const dZapRewardToken = await DZapRewardToken.deploy(dZapStakingAddress, {
    gasPrice: 33000000000,
  });
  await dZapRewardToken.waitForDeployment();
  const dZapRewardTokenAddress = await dZapRewardToken.getAddress();
  console.log("DZapRewardToken Contract Address:", dZapRewardTokenAddress);
  console.log("----------------------------------------------------------");

  // Update DZapRewardToken Contract Address in DZapStaking Contract

  console.log(
    "Updating DZapRewardToken Contract Address in DZapStaking Contract..."
  );
  const dZapStakingContractInstance = await dZapStaking.attach(
    dZapStakingAddress
  );

  const updateDZapRewardAddressInDZapStakingTx =
    await dZapStakingContractInstance.updateRewardTokenContractAddress(
      dZapRewardTokenAddress
    );
  await updateDZapRewardAddressInDZapStakingTx.wait();
  console.log("DZapStakingContract updated successfully.");
  console.log("----------------------------------------------------------");

  // Verify DZapNfts Contract
  console.log("Verifying DZapNfts...");
  await run("verify:verify", {
    address: dZapNftsAddress,
    constructorArguments: [],
  });
  console.log("----------------------------------------------------------");

  // Verify DZapStaking Contract
  console.log("Verifying DZapStaking...");
  await run("verify:verify", {
    address: dZapStakingAddress,
    constructorArguments: [dZapNftsAddress],
  });
  console.log("----------------------------------------------------------");

  // Verify DZapRewardToken Contract
  console.log("Verifying DZapRewardToken...");
  await run("verify:verify", {
    address: dZapRewardTokenAddress,
    constructorArguments: [dZapStakingAddress],
  });
  console.log("----------------------------------------------------------");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });

// CLI command to deploy all contracts at once
// yarn hardhat run scripts/DeployAll.js --network polygonAmoy
// yarn hardhat verify --network polygonAmoy DEPLOYED_CONTRACT_ADDRESS
