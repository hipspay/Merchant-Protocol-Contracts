# MerchantProtocolADM Contract User Manual

## Table of Contents
1. [Introduction](#introduction)
2. [Contract Deployment](#contract-deployment)
3. [Key Concepts](#key-concepts)
4. [Functions](#functions)
5. [Reputation System](#reputation-system)
6. [Automatic Dispute Management (ADM)](#automatic-dispute-management-adm)
7. [Industry-Specific Escrow Periods](#industry-specific-escrow-periods)
8. [Best Practices and Security Considerations](#best-practices-and-security-considerations)

## Introduction

The MerchantProtocolADM contract is a sophisticated escrow system designed to facilitate secure transactions between buyers and merchants. It incorporates an Automatic Dispute Management (ADM) system and a reputation mechanism to ensure fair trade practices.

A demo react app to interact with the contract can be found here:
https://github.com/hipspay/Merchant-Protocol-ADM-Interaction


## Contract Deployment

The contract is deployed at:
https://etherscan.io/address/0x6B061bAe16E702c76C0D0537c8bf1928F2D7D2ec

To deploy the contract, you need:
- The address of the MTO token contract
- The address of the MTO controller account

Deploy the contract by calling the constructor with these two parameters:

```solidity

_mtoToken = 0xE66b3AA360bB78468c00Bebe163630269DB3324F
_mtoControllerAccount = 0x4671d5e6821EaCfA0F0d16a5Fd4D60c804E7d4e0

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
   - Withdraws accumulated MTO tokens from the contract into a MTO staking contract.

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

# Industry-Specific Escrow Periods

Below is a list of industries with suggested escrow periods. These periods take into account the typical time needed for service delivery or product shipping and potential issues to surface:

1. **Digital Products (e.g., software, e-books)**
   - Escrow Period: 1-3 days
   - Rationale: Immediate delivery, short time needed to verify functionality or content

2. **Online Services (e.g., freelance work, consulting)**
   - Escrow Period: 3-7 days
   - Rationale: Time for service delivery and client review

3. **Retail (Physical Products)**
   - Escrow Period: 10-14 days
   - Rationale: Allows for shipping time and product inspection

4. **Handmade or Custom Products**
   - Escrow Period: 14-21 days
   - Rationale: Longer production and shipping times, time for customer to verify customizations

5. **Real Estate**
   - Escrow Period: 30-60 days
   - Rationale: Time for property inspections, mortgage approval, and legal processes

6. **Automotive**
   - Escrow Period: 7-14 days
   - Rationale: Time for vehicle inspection, test drive, and potential repairs

7. **Travel and Hospitality**
   - Escrow Period: 1-3 days after check-out date
   - Rationale: Covers the duration of stay plus time for post-stay issues to surface

8. **Event Planning Services**
   - Escrow Period: 3-7 days after event date
   - Rationale: Covers the event itself and time for post-event review

9. **Home Improvement Services**
   - Escrow Period: 14-30 days
   - Rationale: Time for project completion and thorough inspection of work

10. **Education and Online Courses**
    - Escrow Period: 14-30 days
    - Rationale: Time for student to access and evaluate course content

Note: These are suggested periods and may need to be adjusted based on specific circumstances, local regulations, or company policies. It's important to clearly communicate the escrow period to both buyers and sellers to ensure transparency in the transaction process.



## Best Practices and Security Considerations

1. Always verify transaction IDs and statuses before taking actions.
2. Buyers should add protection to important transactions.
3. Merchants should maintain a good reputation by resolving disputes fairly.
4. The contract owner should be a secure, potentially multi-sig wallet.
5. Regularly monitor and audit the contract's behavior and accumulated funds.

Remember, blockchain transactions are irreversible. Always double-check inputs and understand the consequences of each action before executing it.
