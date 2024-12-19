const hre = require("hardhat");

async function main() {
    const COMPLIANCE_ID = 1;
    const ONE_DAY = 24 * 60 * 60;
    
    // Get the current timestamp
    const currentTime = Math.floor(Date.now() / 1000);
    const startTime = currentTime + ONE_DAY; // Starts in 1 day
    const whitelistEndTime = startTime + (7 * ONE_DAY); // Whitelist period: 7 days
    const endTime = startTime + (30 * ONE_DAY); // Total duration: 30 days

    // USDC address on your target network
    const USDC_ADDRESS = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"; // Mainnet USDC
    
    // Get deployer and landlord addresses
    const [deployer, landlord] = await hre.ethers.getSigners();

    // Fundraising parameters (in USDC - 6 decimals)
    const minInvestment = hre.ethers.parseUnits("100", 6); // 100 USDC
    const maxInvestment = hre.ethers.parseUnits("10000", 6); // 10,000 USDC
    const softCap = hre.ethers.parseUnits("50000", 6); // 50,000 USDC
    const hardCap = hre.ethers.parseUnits("100000", 6); // 100,000 USDC
    const tokenPrice = hre.ethers.parseUnits("1", 6); // 1 USDC per token

    // Token parameters
    const tokenName = "BB Property Token";
    const tokenSymbol = "BBPT";

    // Deploy ComplianceRegistry
    const ComplianceRegistry = await hre.ethers.getContractFactory("ComplianceRegistry");
    const complianceRegistry = await ComplianceRegistry.deploy();
    await complianceRegistry.waitForDeployment();
    console.log(`ComplianceRegistry deployed to ${await complianceRegistry.getAddress()}`);

    // Create compliance ID
    await complianceRegistry.createComplianceId(COMPLIANCE_ID);
    console.log(`Created compliance ID: ${COMPLIANCE_ID}`);

    // Deploy BBFundraising (which will deploy BBPropertyToken)
    const BBFundraising = await hre.ethers.getContractFactory("BBFundraising");
    const bbFundraising = await BBFundraising.deploy(
        await complianceRegistry.getAddress(),
        COMPLIANCE_ID,
        USDC_ADDRESS,
        landlord.address,
        startTime,
        endTime,
        whitelistEndTime,
        minInvestment,
        maxInvestment,
        softCap,
        hardCap,
        tokenPrice,
        tokenName,
        tokenSymbol
    );
    await bbFundraising.waitForDeployment();
    console.log(`BBFundraising deployed to ${await bbFundraising.getAddress()}`);

    // Get property token address
    const propertyTokenAddress = await bbFundraising.propertyToken();
    console.log(`BBPropertyToken deployed to ${propertyTokenAddress}`);

    // Get deployer address and approve it
    await complianceRegistry.setAddressApproval(COMPLIANCE_ID, deployer.address, true);
    console.log(`Approved deployer address ${deployer.address}`);

    console.log("\nDeployment Summary:");
    console.log("==================");
    console.log(`Token Name: ${tokenName}`);
    console.log(`Token Symbol: ${tokenSymbol}`);
    console.log(`Payment Token (USDC): ${USDC_ADDRESS}`);
    console.log(`Landlord Address: ${landlord.address}`);
    console.log(`Start Time: ${new Date(startTime * 1000).toISOString()}`);
    console.log(`Whitelist End: ${new Date(whitelistEndTime * 1000).toISOString()}`);
    console.log(`End Time: ${new Date(endTime * 1000).toISOString()}`);
    console.log(`Min Investment: ${hre.ethers.formatUnits(minInvestment, 6)} USDC`);
    console.log(`Max Investment: ${hre.ethers.formatUnits(maxInvestment, 6)} USDC`);
    console.log(`Soft Cap: ${hre.ethers.formatUnits(softCap, 6)} USDC`);
    console.log(`Hard Cap: ${hre.ethers.formatUnits(hardCap, 6)} USDC`);
    console.log(`Token Price: ${hre.ethers.formatUnits(tokenPrice, 6)} USDC`);
}

main().catch((error) => {
    console.error(error);
    process.exitCode = 1;
});
