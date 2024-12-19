// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./ComplianceRegistry.sol";

/**
 * @title BBCoin
 * @dev A utility token for the BBLong platform with compliance checks and role-based access control.
 * Features minting, burning, and compliance-checked transfers.
 *
 * Features:
 * - Role-based minting control
 * - Compliance integration
 * - Secure transfer restrictions
 * - Burning capability
 * - Admin-controlled transfers
 */
contract BBCoin is ERC20, AccessControl, ReentrancyGuard {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    ComplianceRegistry public immutable complianceRegistry;
    uint256 public complianceId;

    event ComplianceIdSet(uint256 indexed complianceId);
    event AdminTransfer(address indexed from, address indexed to, uint256 amount);

    /**
     * @dev Constructor for BBCoin
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
        require(_complianceRegistry != address(0), "Invalid registry address");
        complianceRegistry = ComplianceRegistry(_complianceRegistry);
        complianceId = _complianceId;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(MINTER_ROLE, msg.sender);
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
        complianceId = _complianceId;
        emit ComplianceIdSet(_complianceId);
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
        external 
        onlyRole(MINTER_ROLE) 
    {
        require(complianceRegistry.isApprovedAddress(complianceId, to), "Recipient not approved");
        _mint(to, amount);
    }

    /**
     * @dev Burns tokens from the caller's balance
     * @param amount Amount of tokens to burn
     * Requirements:
     * - Caller must be approved in compliance registry
     */
    function burn(uint256 amount) 
        external 
        nonReentrant 
    {
        require(complianceRegistry.isApprovedAddress(complianceId, msg.sender), "Sender not approved");
        _burn(msg.sender, amount);
    }

    /**
     * @dev Allows admins to transfer tokens between addresses
     * @param from Address to transfer from
     * @param to Address to transfer to
     * @param amount Amount of tokens to transfer
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Both addresses must be approved in compliance registry
     */
    function adminTransfer(
        address from,
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        require(complianceRegistry.isApprovedAddress(complianceId, from), "Sender not approved");
        require(complianceRegistry.isApprovedAddress(complianceId, to), "Recipient not approved");
        
        _transfer(from, to, amount);
        emit AdminTransfer(from, to, amount);
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
    ) internal virtual override {
        if (from != address(0)) {  // Skip check for minting
            require(complianceRegistry.isApprovedAddress(complianceId, from), "Sender not approved");
        }
        if (to != address(0)) {  // Skip check for burning
            require(complianceRegistry.isApprovedAddress(complianceId, to), "Recipient not approved");
        }
        super._beforeTokenTransfer(from, to, amount);
    }
}
