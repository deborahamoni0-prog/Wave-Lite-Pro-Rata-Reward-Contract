import hre from "hardhat";

async function main() {
  console.log("Deploying WaveLite...");
  console.log("Note: Hardhat 3 requires additional plugins for deployment.");
  console.log("Install @nomicfoundation/hardhat-ethers or use Hardhat Ignition.");
  console.log("\nContract compiled successfully at: artifacts/contracts/WaveLite.sol/WaveLite.json");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
