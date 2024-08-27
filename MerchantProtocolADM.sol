// SPDX-License-Identifier: Creative Commons Attribution-NonCommercial (CC BY-NC) License
// Copyright 2024 HIPS Payment Group Ltd (hips.com)

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract MerchantProtocolADM is Ownable {
    IERC20 public immutable mtoToken;
    address public immutable mtoControllerAccount;
    uint256 public constant ESCROW_PERIOD = 3 days; // For Digital Products (e.g., software, e-books). See Industry-Specific Escrow Periods.
    uint256 public constant PROTECTION_FEE = 5 * 10**18; // 5 MTO tokens
    uint256 public constant REPUTATION_THRESHOLD = 50; // Reputation threshold for automatic dispute resolution
    uint256 public constant SIX_MONTHS = 180 days;
    uint256 public constant MIN_TRANSACTIONS_FOR_VALID_REPUTATION = 10;

    enum TxStatus { NotFound, NotProtected, Protected, Disputed, Withdrawn, Chargebacked }

    struct Transaction {
        address buyer;
        address merchant;
        uint256 amount;
        uint256 timestamp;
        TxStatus status;
        address tokenContract;
    }

    struct MerchantReputation {
        uint256 totalTransactions;
        uint256 totalAmount;
        uint256 successfulTransactions;
        uint256 successfulAmount;
        uint256 disputedTransactions;
        uint256 disputedAmount;
        uint256 chargebackedTransactions;
        uint256 chargebackedAmount;
        uint256 creationTimestamp;
        uint256 lastUpdateTimestamp;
    }

    mapping(bytes32 => Transaction) public transactions;
    mapping(address => MerchantReputation) public merchantReputations;

    event FundsSent(bytes32 indexed txId, address indexed buyer, address indexed merchant, uint256 amount, address tokenContract);
    event ProtectionAdded(bytes32 indexed txId);
    event Disputed(bytes32 indexed txId);
    event Withdrawn(bytes32 indexed txId);
    event Chargebacked(bytes32 indexed txId);
    event ReputationUpdated(address indexed merchant, uint256 newReputation, bool isValid);

    constructor(address _mtoToken, address _mtoControllerAccount) Ownable(msg.sender) {
        mtoToken = IERC20(_mtoToken);
        mtoControllerAccount = _mtoControllerAccount;
    }

    function getEscrowPeriod() public pure returns (uint256) {
        return ESCROW_PERIOD;
    }

    function sendFunds(address merchant, address tokenContract, uint256 amount) external returns (bytes32) {
        require(IERC20(tokenContract).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        bytes32 txId = keccak256(abi.encodePacked(msg.sender, merchant, amount, block.timestamp));
        transactions[txId] = Transaction(msg.sender, merchant, amount, block.timestamp, TxStatus.NotProtected, tokenContract);
        
        MerchantReputation storage rep = merchantReputations[merchant];
        if (rep.creationTimestamp == 0) {
            rep.creationTimestamp = block.timestamp;
        }
        rep.totalTransactions++;
        rep.totalAmount += amount;
        rep.lastUpdateTimestamp = block.timestamp;
        
        emit FundsSent(txId, msg.sender, merchant, amount, tokenContract);
        return txId;
    }

    function addProtection(bytes32 txId) external {
        require(transactions[txId].buyer == msg.sender, "Not the buyer");
        require(transactions[txId].status == TxStatus.NotProtected, "Invalid status");
        require(mtoToken.transferFrom(msg.sender, address(this), PROTECTION_FEE), "Protection fee transfer failed");

        transactions[txId].status = TxStatus.Protected;
        emit ProtectionAdded(txId);
    }

    function checkTxStatus(bytes32 txId) external view returns (TxStatus) {
        return transactions[txId].status;
    }

    function withdraw(bytes32 txId) external {
        Transaction storage txn = transactions[txId];
        require(txn.merchant == msg.sender, "Not the merchant");
        require(txn.status == TxStatus.Protected, "Invalid status");
        require(block.timestamp >= txn.timestamp + ESCROW_PERIOD, "Escrow period not ended");

        txn.status = TxStatus.Withdrawn;
        IERC20(txn.tokenContract).transfer(txn.merchant, txn.amount);
        
        MerchantReputation storage rep = merchantReputations[txn.merchant];
        rep.successfulTransactions++;
        rep.successfulAmount += txn.amount;
        rep.lastUpdateTimestamp = block.timestamp;
        
        updateReputation(txn.merchant);
        
        emit Withdrawn(txId);
    }

    function dispute(bytes32 txId) external {
        Transaction storage txn = transactions[txId];
        require(txn.buyer == msg.sender, "Not the buyer");
        require(txn.status == TxStatus.Protected, "Invalid status");
        require(block.timestamp < txn.timestamp + ESCROW_PERIOD, "Escrow period ended");

        txn.status = TxStatus.Disputed;
        
        MerchantReputation storage rep = merchantReputations[txn.merchant];
        rep.disputedTransactions++;
        rep.disputedAmount += txn.amount;
        rep.lastUpdateTimestamp = block.timestamp;
        
        emit Disputed(txId);
        
        // Implement ADM logic
        (uint256 merchantReputation, bool isValid) = calculateReputation(txn.merchant);
        if (!isValid || merchantReputation < REPUTATION_THRESHOLD) {
            _chargeback(txId);
        } else {
            txn.status = TxStatus.Withdrawn;
            IERC20(txn.tokenContract).transfer(txn.merchant, txn.amount);
            rep.successfulTransactions++;
            rep.successfulAmount += txn.amount;
        }
        
        updateReputation(txn.merchant);
    }
    function _chargeback(bytes32 txId) internal {
        Transaction storage txn = transactions[txId];
        require(txn.status == TxStatus.Disputed, "Invalid status"); // Adding a check
        txn.status = TxStatus.Chargebacked;
        bool transferSuccess = IERC20(txn.tokenContract).transfer(txn.buyer, txn.amount);
        require(transferSuccess, "Transfer failed"); // Check if transfer was successful
        
        MerchantReputation storage rep = merchantReputations[txn.merchant];
        rep.chargebackedTransactions++;
        rep.chargebackedAmount += txn.amount;
        rep.lastUpdateTimestamp = block.timestamp;
        
        emit Chargebacked(txId);
    }

    function calculateReputation(address merchant) public view returns (uint256 reputation, bool isValid) {
        MerchantReputation storage rep = merchantReputations[merchant];
        if (rep.totalTransactions < MIN_TRANSACTIONS_FOR_VALID_REPUTATION) {
            return (0, false);
        }
        
        uint256 accountAge = block.timestamp - rep.creationTimestamp;
        uint256 timeSinceLastUpdate = block.timestamp - rep.lastUpdateTimestamp;
        
        uint256 successRate = (rep.successfulAmount * 100) / rep.totalAmount;
        uint256 disputeRate = (rep.disputedAmount * 100) / rep.totalAmount;
        uint256 chargebackRate = (rep.chargebackedAmount * 100) / rep.totalAmount;
        
        // Apply time decay factor
        uint256 decayFactor = timeSinceLastUpdate >= SIX_MONTHS ? 50 : 100 - ((timeSinceLastUpdate * 50) / SIX_MONTHS);
        
        // Calculate base reputation
        uint256 baseReputation = successRate - disputeRate - (chargebackRate * 2);
        
        // Apply decay factor
        uint256 decayedReputation = (baseReputation * decayFactor) / 100;
        
        // Apply account age bonus (max 20% bonus for accounts older than 1 year)
        uint256 ageBonus = accountAge >= 365 days ? 20 : (accountAge * 20) / 365 days;
        
        reputation = decayedReputation + ageBonus;
        isValid = true;
        
        return (reputation, isValid);
    }

    function updateReputation(address merchant) internal {
        (uint256 newReputation, bool isValid) = calculateReputation(merchant);
        emit ReputationUpdated(merchant, newReputation, isValid);
    }

    function withdrawMTO() external {
        require(msg.sender == mtoControllerAccount, "Not authorized");
        uint256 balance = mtoToken.balanceOf(address(this));
        require(mtoToken.transfer(mtoControllerAccount, balance), "Transfer failed");
    }
}
