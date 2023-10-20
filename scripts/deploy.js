const hre = require("hardhat");

async function main(){
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deploy contracts with:", deployer.address);

  const metatandasFactory = await hre.ethers.getContractFactory("Tanda");
  const metatandas = await metatandasFactory.deploy("MetaTanda", "Tanda test",2,1);
  metatandas.deployed();

  console.log("Contract deployed: ", metatandas.address);

  
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
      console.error(error);
      process.exit(1);
  });