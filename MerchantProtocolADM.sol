// SPDX-License-Identifier: Creative Commons Attribution-NonCommercial (CC BY-NC) License
// Copyright 2024 - HIPS Payment Group Ltd (hips.com)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract MerchantProtocolADM is Ownable {
    using SafeMath for uint256;

    IERC20 public mtoToken;
    address public mtoControllerAccount;
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

    event FundsSent(bytes32 txId, address buyer, address merchant, uint256 amount, address tokenContract);
    event ProtectionAdded(bytes32 txId);
    event Disputed(bytes32 txId);
    event Withdrawn(bytes32 txId);
    event Chargebacked(bytes32 txId);
    event ReputationUpdated(address merchant, uint256 newReputation, bool isValid);

    constructor(address _mtoToken, address _mtoControllerAccount) {
        mtoToken = IERC20(_mtoToken);
        mtoControllerAccount = _mtoControllerAccount;
    }

    function sendFunds(address merchant, address tokenContract, uint256 amount) external returns (bytes32) {
        require(IERC20(tokenContract).transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        bytes32 txId = keccak256(abi.encodePacked(msg.sender, merchant, amount, block.timestamp));
        transactions[txId] = Transaction(msg.sender, merchant, amount, block.timestamp, TxStatus.NotProtected, tokenContract);
        
        MerchantReputation storage rep = merchantReputations[merchant];
        if (rep.creationTimestamp == 0) {
            rep.creationTimestamp = block.timestamp;
        }
        rep.totalTransactions = rep.totalTransactions.add(1);
        rep.totalAmount = rep.totalAmount.add(amount);
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
        Transaction storage tx = transactions[txId];
        require(tx.merchant == msg.sender, "Not the merchant");
        require(tx.status == TxStatus.Protected, "Invalid status");
        require(block.timestamp >= tx.timestamp + ESCROW_PERIOD, "Escrow period not ended");

        tx.status = TxStatus.Withdrawn;
        IERC20(tx.tokenContract).transfer(tx.merchant, tx.amount);
        
        MerchantReputation storage rep = merchantReputations[tx.merchant];
        rep.successfulTransactions = rep.successfulTransactions.add(1);
        rep.successfulAmount = rep.successfulAmount.add(tx.amount);
        rep.lastUpdateTimestamp = block.timestamp;
        
        updateReputation(tx.merchant);
        
        emit Withdrawn(txId);
    }

    function dispute(bytes32 txId) external {
        Transaction storage tx = transactions[txId];
        require(tx.buyer == msg.sender, "Not the buyer");
        require(tx.status == TxStatus.Protected, "Invalid status");
        require(block.timestamp < tx.timestamp + ESCROW_PERIOD, "Escrow period ended");

        tx.status = TxStatus.Disputed;
        
        MerchantReputation storage rep = merchantReputations[tx.merchant];
        rep.disputedTransactions = rep.disputedTransactions.add(1);
        rep.disputedAmount = rep.disputedAmount.add(tx.amount);
        rep.lastUpdateTimestamp = block.timestamp;
        
        emit Disputed(txId);
        
        // Implement ADM logic
        (uint256 merchantReputation, bool isValid) = calculateReputation(tx.merchant);
        if (!isValid || merchantReputation < REPUTATION_THRESHOLD) {
            _chargeback(txId);
        } else {
            tx.status = TxStatus.Withdrawn;
            IERC20(tx.tokenContract).transfer(tx.merchant, tx.amount);
            rep.successfulTransactions = rep.successfulTransactions.add(1);
            rep.successfulAmount = rep.successfulAmount.add(tx.amount);
        }
        
        updateReputation(tx.merchant);
    }

    function _chargeback(bytes32 txId) internal {
        Transaction storage tx = transactions[txId];
        tx.status = TxStatus.Chargebacked;
        IERC20(tx.tokenContract).transfer(tx.buyer, tx.amount);
        
        MerchantReputation storage rep = merchantReputations[tx.merchant];
        rep.chargebackedTransactions = rep.chargebackedTransactions.add(1);
        rep.chargebackedAmount = rep.chargebackedAmount.add(tx.amount);
        rep.lastUpdateTimestamp = block.timestamp;
        
        emit Chargebacked(txId);
    }

    function calculateReputation(address merchant) public view returns (uint256 reputation, bool isValid) {
        MerchantReputation storage rep = merchantReputations[merchant];
        if (rep.totalTransactions < MIN_TRANSACTIONS_FOR_VALID_REPUTATION) {
            return (0, false);
        }
        
        uint256 accountAge = block.timestamp.sub(rep.creationTimestamp);
        uint256 timeSinceLastUpdate = block.timestamp.sub(rep.lastUpdateTimestamp);
        
        uint256 successRate = rep.successfulAmount.mul(100).div(rep.totalAmount);
        uint256 disputeRate = rep.disputedAmount.mul(100).div(rep.totalAmount);
        uint256 chargebackRate = rep.chargebackedAmount.mul(100).div(rep.totalAmount);
        
        // Apply time decay factor
        uint256 decayFactor = timeSinceLastUpdate >= SIX_MONTHS ? 50 : 100 - (timeSinceLastUpdate.mul(50).div(SIX_MONTHS));
        
        // Calculate base reputation
        uint256 baseReputation = successRate.sub(disputeRate).sub(chargebackRate.mul(2));
        
        // Apply decay factor
        uint256 decayedReputation = baseReputation.mul(decayFactor).div(100);
        
        // Apply account age bonus (max 20% bonus for accounts older than 1 year)
        uint256 ageBonus = accountAge >= 365 days ? 20 : accountAge.mul(20).div(365 days);
        
        reputation = decayedReputation.add(ageBonus);
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

