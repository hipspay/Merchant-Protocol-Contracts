# MerchantProtocolADM Contract User Manual

## Table of Contents
1. [Introduction](#introduction)
2. [Contract Deployment](#contract-deployment)
3. [Key Concepts](#key-concepts)
4. [Functions](#functions)
5. [Reputation System](#reputation-system)
6. [Automatic Dispute Management (ADM)](#automatic-dispute-management-adm)
7. [Best Practices and Security Considerations](#best-practices-and-security-considerations)

## Introduction

The MerchantProtocolADM contract is a sophisticated escrow system designed to facilitate secure transactions between buyers and merchants. It incorporates an Automatic Dispute Management (ADM) system and a reputation mechanism to ensure fair trade practices.

## Contract Deployment

To deploy the contract, you need:
- The address of the MTO token contract
- The address of the MTO controller account

Deploy the contract by calling the constructor with these two parameters:

```solidity
constructor(address _mtoToken, address _mtoControllerAccount)
```

## Key Concepts

1. **Transaction**: A fund transfer from a buyer to a merchant, held in escrow.
2. **Protection**: Additional security for a transaction, activated by paying a fee in MTO tokens.
3. **Escrow Period**: The time (5 days) during which funds are held before being released to the merchant.
4. **Reputation**: A score calculated for each merchant based on their transaction history.
5. **Dispute**: A claim raised by a buyer against a transaction during the escrow period.

## Functions

### For Buyers

1. `sendFunds(address merchant, address tokenContract, uint256 amount) -> bytes32`
   - Initiates a transaction, returning a unique transaction ID.

2. `addProtection(bytes32 txId)`
   - Adds protection to a transaction by paying the protection fee in MTO tokens.

3. `dispute(bytes32 txId)`
   - Raises a dispute for a protected transaction during the escrow period.

### For Merchants

1. `withdraw(bytes32 txId)`
   - Withdraws funds from a successful transaction after the escrow period.

### For Anyone

1. `checkTxStatus(bytes32 txId) -> TxStatus`
   - Checks the status of a transaction.

2. `calculateReputation(address merchant) -> (uint256 reputation, bool isValid)`
   - Calculates the reputation of a merchant.

### For MTO Controller

1. `withdrawMTO()`
   - Withdraws accumulated MTO tokens from the contract.

## Reputation System

The reputation system considers:
- Total transaction volume
- Successful transactions
- Disputed transactions
- Chargebacked transactions
- Account age
- Time decay (older transactions have less impact)

A minimum of 10 transactions is required for a valid reputation.

## Automatic Dispute Management (ADM)

When a dispute is raised:
1. The contract checks the merchant's reputation.
2. If the reputation is invalid or below the threshold, the transaction is automatically chargebacked.
3. If the reputation is valid and above the threshold, the transaction proceeds in favor of the merchant.

## Best Practices and Security Considerations

1. Always verify transaction IDs and statuses before taking actions.
2. Buyers should add protection to important transactions.
3. Merchants should maintain a good reputation by resolving disputes fairly.
4. The contract owner should be a secure, potentially multi-sig wallet.
5. Regularly monitor and audit the contract's behavior and accumulated funds.

Remember, blockchain transactions are irreversible. Always double-check inputs and understand the consequences of each action before executing it.
