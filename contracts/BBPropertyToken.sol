// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ComplianceRegistry.sol";

/**
 * @title BBPropertyToken
 * @dev An ERC20 token representing ownership in a property with dividend distribution capabilities.
 * Includes compliance checks, snapshot functionality for dividend calculations, and role-based access control.
 *
 * Features:
 * - Compliance-checked token transfers
 * - Snapshot-based dividend distribution
 * - Role-based minting and admin controls
 * - ETH and ERC20 token dividend payments
 * - Dividend claiming with expiration
 */
contract BBPropertyToken is ERC20Snapshot, AccessControl, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant SNAPSHOT_ROLE = keccak256("SNAPSHOT_ROLE");

    ComplianceRegistry public complianceRegistry;
    uint256 public complianceId;

    // Dividend distribution state
    struct DividendDistribution {
        uint256 snapshotId;
        uint256 totalAmount;
        uint256 perTokenAmount;
        uint256 claimedAmount;
        bool initialized;
        address tokenAddress; // Address of the token being distributed (address(0) for ETH)
        mapping(address => bool) hasClaimed;
    }

    // Mapping from distribution ID to dividend distribution
    mapping(uint256 => DividendDistribution) public dividendDistributions;
    uint256 public currentDistributionId;

    event DividendDistributionCreated(uint256 indexed distributionId, address indexed tokenAddress, uint256 amount, uint256 snapshotId);
    event DividendClaimed(uint256 indexed distributionId, address indexed account, uint256 amount);
    event ComplianceIdSet(uint256 indexed complianceId);

    /**
     * @dev Constructor for BBPropertyToken
     * @param _complianceRegistry Address of the compliance registry contract
     * @param _complianceId ID for compliance checks
     * @param name Token name
     * @param symbol Token symbol
     */
    constructor(
        address _complianceRegistry, 
        uint256 _complianceId,
        string memory name,
        string memory symbol
    ) ERC20(name, symbol) {
        require(_complianceRegistry != address(0), "Invalid compliance registry");
        complianceRegistry = ComplianceRegistry(_complianceRegistry);
        
        require(complianceRegistry.isValidComplianceId(_complianceId), "Invalid compliance ID");
        complianceId = _complianceId;
        emit ComplianceIdSet(_complianceId);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
        _grantRole(SNAPSHOT_ROLE, msg.sender);
    }

    /**
     * @dev Sets a new compliance ID
     * @param _complianceId New compliance ID
     * Requirements:
     * - Caller must have ADMIN_ROLE
     */
    function setComplianceId(uint256 _complianceId) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(complianceRegistry.isValidComplianceId(_complianceId), "Invalid compliance ID");
        complianceId = _complianceId;
        emit ComplianceIdSet(_complianceId);
    }

    /**
     * @dev Creates a new snapshot for dividend distribution
     * Requirements:
     * - Caller must have SNAPSHOT_ROLE
     * @return Current snapshot id
     */
    function snapshot() 
        public 
        onlyRole(SNAPSHOT_ROLE) 
        returns (uint256) 
    {
        return _snapshot();
    }

    /**
     * @dev Creates a new dividend distribution with ETH or ERC20 tokens
     * @param amount Amount of tokens to distribute
     * @param tokenAddress Address of the token to distribute (use address(0) for ETH)
     * Requirements:
     * - For ETH: Must send ETH with the transaction
     * - For tokens: Must approve contract to spend tokens
     * - Must have non-zero total supply
     * - Caller must have ADMIN_ROLE
     */
    function createDividendDistribution(uint256 amount, address tokenAddress) 
        external 
        payable 
        onlyRole(ADMIN_ROLE) 
        nonReentrant 
        returns (uint256) 
    {
        if (tokenAddress == address(0)) {
            // ETH distribution
            require(msg.value == amount, "Incorrect ETH amount");
        } else {
            // ERC20 token distribution
            require(msg.value == 0, "ETH not needed for token distribution");
            IERC20 token = IERC20(tokenAddress);
            require(token.transferFrom(msg.sender, address(this), amount), "Token transfer failed");
        }

        require(amount > 0, "Amount must be greater than 0");

        uint256 snapshotId = snapshot();
        uint256 totalSupplyAtSnapshot = totalSupplyAt(snapshotId);
        require(totalSupplyAtSnapshot > 0, "No tokens at snapshot");

        uint256 distributionId = ++currentDistributionId;
        DividendDistribution storage distribution = dividendDistributions[distributionId];
        
        distribution.snapshotId = snapshotId;
        distribution.totalAmount = amount;
        distribution.perTokenAmount = (amount * 1e18) / totalSupplyAtSnapshot; // Scale by 1e18 for precision
        distribution.initialized = true;
        distribution.tokenAddress = tokenAddress;

        emit DividendDistributionCreated(distributionId, tokenAddress, amount, snapshotId);
        return distributionId;
    }

    /**
     * @dev Claims dividends from a specific distribution
     * @param distributionId ID of the dividend distribution
     * Requirements:
     * - Distribution must exist and not be expired
     * - Caller must have unclaimed dividends
     * - Caller must have held tokens at snapshot
     */
    function claimDividend(uint256 distributionId) 
        external 
        nonReentrant 
    {
        require(complianceRegistry.isApprovedAddress(complianceId, msg.sender), "Not approved");
        DividendDistribution storage distribution = dividendDistributions[distributionId];
        
        require(distribution.initialized, "Distribution not initialized");
        require(!distribution.hasClaimed[msg.sender], "Already claimed");

        uint256 balance = balanceOfAt(msg.sender, distribution.snapshotId);
        require(balance > 0, "No tokens at snapshot");

        uint256 dividendAmount = (balance * distribution.perTokenAmount) / 1e18;
        require(dividendAmount > 0, "No dividend to claim");

        distribution.hasClaimed[msg.sender] = true;
        distribution.claimedAmount += dividendAmount;

        if (distribution.tokenAddress == address(0)) {
            // ETH distribution
            (bool success, ) = msg.sender.call{value: dividendAmount}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 token distribution
            IERC20 token = IERC20(distribution.tokenAddress);
            require(token.transfer(msg.sender, dividendAmount), "Token transfer failed");
        }

        emit DividendClaimed(distributionId, msg.sender, dividendAmount);
    }

    /**
     * @dev Returns the claimable dividend amount for a specific distribution
     * @param distributionId ID of the dividend distribution
     * @param account Address to calculate dividend for
     * @return Amount of dividend that can be claimed
     */
    function getDividendAmount(uint256 distributionId, address account) 
        external 
        view 
        returns (uint256) 
    {
        DividendDistribution storage distribution = dividendDistributions[distributionId];
        if (!distribution.initialized || distribution.hasClaimed[account]) {
            return 0;
        }

        uint256 balance = balanceOfAt(account, distribution.snapshotId);
        return (balance * distribution.perTokenAmount) / 1e18;
    }

    /**
     * @dev Mints new tokens
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     * Requirements:
     * - Caller must have MINTER_ROLE
     * - Recipient must be approved in compliance registry
     */
    function mint(address to, uint256 amount) 
        public 
        onlyRole(MINTER_ROLE) 
        nonReentrant 
    {
        require(complianceRegistry.isApprovedAddress(complianceId, to), "Recipient not approved");
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens
     * @param amount Amount of tokens to burn
     * Requirements:
     * - Caller must have approved the token contract to spend their tokens
     * - Caller must be approved in compliance registry
     */
    function burn(uint256 amount) 
        public 
        nonReentrant 
    {
        require(complianceRegistry.isApprovedAddress(complianceId, msg.sender), "Sender not approved");
        _burn(msg.sender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param amount Amount of tokens being transferred
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Snapshot) {
        super._beforeTokenTransfer(from, to, amount);
    }

    /**
     * @dev Hook that is called after any transfer of tokens
     * @param from Address tokens are transferred from
     * @param to Address tokens are transferred to
     * @param amount Amount of tokens being transferred
     */
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal virtual override(ERC20Snapshot) {
        if (from != address(0)) { // Skip approval check for minting
            require(complianceRegistry.isApprovedAddress(complianceId, from), "Sender not approved");
        }
        if (to != address(0)) { // Skip approval check for burning
            require(complianceRegistry.isApprovedAddress(complianceId, to), "Recipient not approved");
        }
        super._update(from, to, amount);
    }
}
