const hre = require("hardhat");

async function main() {
  const COMPLIANCE_ID = 1; // Default compliance ID

  // Deploy ComplianceRegistry first
  const ComplianceRegistry = await hre.ethers.getContractFactory("ComplianceRegistry");
  const complianceRegistry = await ComplianceRegistry.deploy();
  await complianceRegistry.waitForDeployment();

  console.log(`ComplianceRegistry deployed to ${await complianceRegistry.getAddress()}`);

  // Create compliance ID
  const createComplianceTx = await complianceRegistry.createComplianceId(COMPLIANCE_ID);
  await createComplianceTx.wait();
  console.log(`Created compliance ID: ${COMPLIANCE_ID}`);

  // Deploy BBCoin with ComplianceRegistry address and compliance ID
  const BBCoin = await hre.ethers.getContractFactory("BBCoin");
  const bbcoin = await BBCoin.deploy(await complianceRegistry.getAddress(), COMPLIANCE_ID);
  await bbcoin.waitForDeployment();

  console.log(`BBCoin deployed to ${await bbcoin.getAddress()}`);

  // Get deployer address
  const [deployer] = await hre.ethers.getSigners();
  console.log(`Deployed by ${deployer.address}`);

  // Approve deployer address in the compliance registry
  const approveTx = await complianceRegistry.setAddressApproval(COMPLIANCE_ID, deployer.address, true);
  await approveTx.wait();
  console.log(`Approved deployer address ${deployer.address} for compliance ID ${COMPLIANCE_ID}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
