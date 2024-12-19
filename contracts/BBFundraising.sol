// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./BBPropertyToken.sol";
import "./ComplianceRegistry.sol";

/**
 * @title BBFundraising
 * @dev A contract for managing property token fundraising with USDC payments and compliance checks.
 * Supports whitelisting, soft/hard caps, and automatic token distribution.
 *
 * Features:
 * - USDC-based investments
 * - Compliance registry integration
 * - Whitelist period for early investors
 * - Configurable investment limits
 * - Automatic token distribution on successful fundraising
 * - Refund capability on failed fundraising
 */
contract BBFundraising is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    BBPropertyToken public propertyToken;
    ComplianceRegistry public complianceRegistry;
    uint256 public complianceId;
    IERC20 public paymentToken;
    address public landlord;

    uint256 public startTime;
    uint256 public endTime;
    uint256 public minInvestment;
    uint256 public maxInvestment;
    uint256 public softCap;
    uint256 public hardCap;
    uint256 public tokenPrice; // Price in payment token units per property token (scaled by 1e18)
    
    uint256 public totalRaised;
    mapping(address => uint256) public investments;
    
    bool public isFinalized;
    bool public isSuccessful;
    
    // Whitelist for early investors
    mapping(address => bool) public whitelist;
    uint256 public whitelistEndTime;
    
    event PropertyTokenDeployed(address indexed tokenAddress);
    event Invested(address indexed investor, uint256 amount);
    event Refunded(address indexed investor, uint256 amount);
    event TokensClaimed(address indexed investor, uint256 amount);
    event FundraisingFinalized(bool successful, uint256 totalRaised);
    event WhitelistUpdated(address indexed investor, bool status);
    event PaymentTokenUpdated(address indexed newPaymentToken);
    event LandlordUpdated(address indexed newLandlord);

    /**
     * @dev Constructor for BBFundraising
     * @param _complianceRegistry Address of the compliance registry contract
     * @param _complianceId ID for compliance checks
     * @param _paymentToken Address of the USDC or other ERC20 payment token
     * @param _landlord Address to receive raised funds on successful fundraising
     * @param _startTime Timestamp when fundraising starts
     * @param _endTime Timestamp when fundraising ends
     * @param _whitelistEndTime Timestamp when whitelist period ends
     * @param _minInvestment Minimum investment amount in payment token units
     * @param _maxInvestment Maximum investment amount in payment token units
     * @param _softCap Minimum amount to raise for successful fundraising
     * @param _hardCap Maximum amount that can be raised
     * @param _tokenPrice Price per token in payment token units
     * @param tokenName Name for the property token
     * @param tokenSymbol Symbol for the property token
     */
    constructor(
        address _complianceRegistry,
        uint256 _complianceId,
        address _paymentToken,
        address _landlord,
        uint256 _startTime,
        uint256 _endTime,
        uint256 _whitelistEndTime,
        uint256 _minInvestment,
        uint256 _maxInvestment,
        uint256 _softCap,
        uint256 _hardCap,
        uint256 _tokenPrice,
        string memory tokenName,
        string memory tokenSymbol
    ) {
        require(_complianceRegistry != address(0), "Invalid registry address");
        require(_paymentToken != address(0), "Invalid payment token");
        require(_landlord != address(0), "Invalid landlord address");
        require(_startTime > block.timestamp, "Invalid start time");
        require(_whitelistEndTime >= _startTime, "Invalid whitelist end time");
        require(_endTime > _whitelistEndTime, "Invalid end time");
        require(_minInvestment > 0, "Invalid min investment");
        require(_maxInvestment >= _minInvestment, "Invalid max investment");
        require(_softCap > 0, "Invalid soft cap");
        require(_hardCap >= _softCap, "Invalid hard cap");
        require(_tokenPrice > 0, "Invalid token price");
        require(bytes(tokenName).length > 0, "Invalid token name");
        require(bytes(tokenSymbol).length > 0, "Invalid token symbol");

        complianceRegistry = ComplianceRegistry(_complianceRegistry);
        complianceId = _complianceId;
        paymentToken = IERC20(_paymentToken);
        landlord = _landlord;
        startTime = _startTime;
        endTime = _endTime;
        whitelistEndTime = _whitelistEndTime;
        minInvestment = _minInvestment;
        maxInvestment = _maxInvestment;
        softCap = _softCap;
        hardCap = _hardCap;
        tokenPrice = _tokenPrice;

        // Deploy BBPropertyToken
        propertyToken = new BBPropertyToken(
            _complianceRegistry,
            _complianceId,
            tokenName,
            tokenSymbol
        );
        emit PropertyTokenDeployed(address(propertyToken));

        // Grant roles
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);

        // Grant minter role to this contract
        propertyToken.grantRole(propertyToken.MINTER_ROLE(), address(this));
    }

    /**
     * @dev Updates the payment token address
     * @param _paymentToken New payment token address
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Fundraising must not be finalized
     * - No investments must have been made
     */
    function setPaymentToken(address _paymentToken) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_paymentToken != address(0), "Invalid payment token");
        require(!isFinalized, "Fundraising already finalized");
        require(totalRaised == 0, "Fundraising already started");
        paymentToken = IERC20(_paymentToken);
        emit PaymentTokenUpdated(_paymentToken);
    }

    /**
     * @dev Updates the landlord address
     * @param _landlord New landlord address to receive funds
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function setLandlord(address _landlord) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(_landlord != address(0), "Invalid landlord address");
        landlord = _landlord;
        emit LandlordUpdated(_landlord);
    }

    /**
     * @dev Allows investors to participate in the fundraising
     * @param amount Amount of payment tokens to invest
     * Requirements:
     * - Fundraising must be active
     * - Investor must be approved in compliance registry
     * - Investment amount must be within limits
     * - Total raised must not exceed hard cap
     * - If in whitelist period, investor must be whitelisted
     */
    function invest(uint256 amount)
        external
        nonReentrant
        whenNotPaused
    {
        require(block.timestamp >= startTime, "Fundraising not started");
        require(block.timestamp <= endTime, "Fundraising ended");
        require(!isFinalized, "Fundraising finalized");
        require(complianceRegistry.isApprovedAddress(complianceId, msg.sender), "Not approved");
        
        // Check whitelist period
        if (block.timestamp <= whitelistEndTime) {
            require(whitelist[msg.sender], "Not whitelisted");
        }

        uint256 newInvestment = investments[msg.sender] + amount;
        require(newInvestment >= minInvestment, "Below min investment");
        require(newInvestment <= maxInvestment, "Exceeds max investment");
        
        uint256 newTotalRaised = totalRaised + amount;
        require(newTotalRaised <= hardCap, "Exceeds hard cap");

        // Transfer payment tokens to this contract
        paymentToken.safeTransferFrom(msg.sender, address(this), amount);

        investments[msg.sender] = newInvestment;
        totalRaised = newTotalRaised;

        emit Invested(msg.sender, amount);
    }

    /**
     * @dev Finalizes the fundraising, determining success or failure
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Must be after end time or reached hard cap
     * - Must not be already finalized
     * @notice If successful, transfers all raised funds to landlord
     */
    function finalize()
        external
        onlyRole(ADMIN_ROLE)
        nonReentrant
    {
        require(block.timestamp > endTime || totalRaised >= hardCap, "Cannot finalize yet");
        require(!isFinalized, "Already finalized");

        isFinalized = true;
        isSuccessful = totalRaised >= softCap;

        emit FundraisingFinalized(isSuccessful, totalRaised);

        if (isSuccessful) {
            // Transfer raised tokens to landlord
            paymentToken.safeTransfer(landlord, totalRaised);
        }
    }

    /**
     * @dev Allows investors to claim their property tokens after successful fundraising
     * Requirements:
     * - Fundraising must be finalized and successful
     * - Investor must have unclaimed investment
     */
    function claimTokens()
        external
        nonReentrant
    {
        require(isFinalized, "Not finalized");
        require(isSuccessful, "Fundraising failed");
        require(investments[msg.sender] > 0, "No investment");
        
        uint256 investmentAmount = investments[msg.sender];
        uint256 tokenAmount = (investmentAmount * 1e18) / tokenPrice;
        
        investments[msg.sender] = 0;
        
        require(propertyToken.mint(msg.sender, tokenAmount), "Minting failed");
        
        emit TokensClaimed(msg.sender, tokenAmount);
    }

    /**
     * @dev Allows investors to claim refunds after failed fundraising
     * Requirements:
     * - Fundraising must be finalized and failed
     * - Investor must have unclaimed investment
     */
    function claimRefund()
        external
        nonReentrant
    {
        require(isFinalized, "Not finalized");
        require(!isSuccessful, "Fundraising successful");
        require(investments[msg.sender] > 0, "No investment");
        
        uint256 refundAmount = investments[msg.sender];
        investments[msg.sender] = 0;
        
        paymentToken.safeTransfer(msg.sender, refundAmount);
        
        emit Refunded(msg.sender, refundAmount);
    }

    /**
     * @dev Calculates how many tokens an investor will receive
     * @param investor Address of the investor
     * @return Amount of tokens the investor can claim
     */
    function getInvestorTokens(address investor) 
        external 
        view 
        returns (uint256) 
    {
        if (!isFinalized || !isSuccessful) return 0;
        return (investments[investor] * 1e18) / tokenPrice;
    }

    /**
     * @dev Updates the whitelist status for multiple investors
     * @param investors Array of investor addresses
     * @param status Whitelist status to set
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function updateWhitelist(address[] calldata investors, bool status)
        external
        onlyRole(ADMIN_ROLE)
    {
        for (uint256 i = 0; i < investors.length; i++) {
            whitelist[investors[i]] = status;
            emit WhitelistUpdated(investors[i], status);
        }
    }

    /**
     * @dev Pauses all investment activity
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @dev Resumes all investment activity
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}
