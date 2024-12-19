// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title ComplianceRegistry
 * @dev A registry for managing KYC/AML compliance approvals for different compliance IDs.
 * Allows for multiple compliance levels and batch operations.
 *
 * Features:
 * - Multiple compliance IDs for different requirements
 * - Batch approval operations
 * - Role-based access control
 * - Compliance status tracking
 */
contract ComplianceRegistry is AccessControl, ReentrancyGuard {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant COMPLIANCE_ROLE = keccak256("COMPLIANCE_ROLE");

    // Mapping: complianceId => address => approval status
    mapping(uint256 => mapping(address => bool)) private _approvedAddresses;
    
    // Mapping to track existing compliance IDs
    mapping(uint256 => bool) private _complianceIds;

    event AddressApproved(uint256 indexed complianceId, address indexed account, bool status);
    event ComplianceIdCreated(uint256 indexed complianceId);

    /**
     * @dev Constructor that grants admin roles to the deployer
     */
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(COMPLIANCE_ROLE, msg.sender);
    }

    /**
     * @dev Creates a new compliance ID
     * @param complianceId ID to create
     * Requirements:
     * - Caller must have ADMIN_ROLE
     * - Compliance ID must not already exist
     */
    function createComplianceId(uint256 complianceId) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        require(!_complianceIds[complianceId], "Compliance ID already exists");
        _complianceIds[complianceId] = true;
        emit ComplianceIdCreated(complianceId);
    }

    /**
     * @dev Sets approval status for a single address
     * @param complianceId ID to set approval for
     * @param account Address to approve/disapprove
     * @param status New approval status
     * Requirements:
     * - Caller must have COMPLIANCE_ROLE
     * - Compliance ID must exist
     */
    function setAddressApproval(
        uint256 complianceId,
        address account, 
        bool status
    ) 
        external 
        onlyRole(COMPLIANCE_ROLE) 
        nonReentrant 
    {
        require(_complianceIds[complianceId], "Compliance ID does not exist");
        _approvedAddresses[complianceId][account] = status;
        emit AddressApproved(complianceId, account, status);
    }

    /**
     * @dev Sets approval status for multiple addresses
     * @param complianceId ID to set approvals for
     * @param accounts Array of addresses to approve/disapprove
     * @param status New approval status
     * Requirements:
     * - Caller must have COMPLIANCE_ROLE
     * - Compliance ID must exist
     */
    function batchSetAddressApproval(
        uint256 complianceId,
        address[] calldata accounts, 
        bool status
    ) 
        external 
        onlyRole(COMPLIANCE_ROLE) 
        nonReentrant 
    {
        require(_complianceIds[complianceId], "Compliance ID does not exist");
        for(uint i = 0; i < accounts.length; i++) {
            _approvedAddresses[complianceId][accounts[i]] = status;
            emit AddressApproved(complianceId, accounts[i], status);
        }
    }

    /**
     * @dev Checks if an address is approved for a compliance ID
     * @param complianceId ID to check approval for
     * @param account Address to check
     * @return True if the address is approved
     */
    function isApprovedAddress(uint256 complianceId, address account) 
        external 
        view 
        returns (bool) 
    {
        require(_complianceIds[complianceId], "Compliance ID does not exist");
        return _approvedAddresses[complianceId][account];
    }

    /**
     * @dev Checks if a compliance ID exists
     * @param complianceId ID to check
     * @return True if the compliance ID exists
     */
    function isValidComplianceId(uint256 complianceId) 
        external 
        view 
        returns (bool) 
    {
        return _complianceIds[complianceId];
    }
}
