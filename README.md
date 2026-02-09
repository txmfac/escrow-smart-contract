# EscrowContract (Solidity + Foundry)

A minimal **multi-escrow** smart contract that holds ETH and releases it based on a simple state machine:

- **Buyer** creates an escrow by depositing ETH.
- **Seller** accepts the escrow to start the timer.
- **Buyer** can **release** funds to the seller.
- **Buyer** can **refund** after a timeout (if still funded).
- **Buyer or seller** can **dispute**.
- **Arbiter** resolves a dispute by **releasing** or **refunding**.

Built for learning and practice with **Foundry**.

---

## Contract Overview

### Roles
- **Buyer**: creates the escrow and deposits ETH.
- **Seller**: accepts the escrow.
- **Arbiter**: resolves disputes.

### Escrow States
- `Created` — escrow exists, waiting for seller acceptance
- `Funded` — seller accepted, funds are locked and timer starts
- `Released` — seller has been paid (final)
- `Refunded` — buyer has been refunded (final)
- `Disputed` — waiting for arbiter decision
- `Canceled` — buyer canceled before acceptance (final)

---

## Functions

### `createEscrow(address seller, address arbiter, uint256 timeout) payable -> (uint256 id)`
Creates a new escrow and stores the deposited ETH inside the contract.

**Requirements**
- `seller != address(0)`
- `arbiter != address(0)`
- `msg.value > 0`
- `timeout >= 3 days` (your minimum timeout rule)

**Effects**
- Creates a new escrow with state `Created`
- Stores:
  - buyer = `msg.sender`
  - price = `msg.value`
  - timeout = `_timeout`
  - startedAt = `0`

**Emits**
- `EscrowCreated(id, buyer, seller, arbiter)`

---

### `acceptEscrow(uint256 id)`
Seller accepts the escrow and starts the timer.

**Requirements**
- escrow exists
- caller is the seller
- state is `Created`

**Effects**
- state becomes `Funded`
- `startedAt = block.timestamp`

**Emits**
- `EscrowAccepted(id)`

---

### `cancelEscrow(uint256 id)`
Buyer cancels the escrow **only before** the seller accepts.

**Requirements**
- escrow exists
- caller is the buyer
- state is `Created`

**Effects**
- state becomes `Canceled`
- buyer receives the escrow `price`

**Emits**
- `EscrowCanceled(id)`

---

### `releaseEscrow(uint256 id)`
Buyer releases the funds to the seller.

**Requirements**
- escrow exists
- caller is the buyer
- state is `Funded`

**Effects**
- state becomes `Released`
- seller receives the escrow `price`

**Emits**
- `EscrowReleased(id)`

---

### `refundEscrow(uint256 id)`
Buyer refunds themselves **after the timeout**.

**Requirements**
- escrow exists
- caller is the buyer
- state is `Funded`
- `block.timestamp >= startedAt + timeout`

**Effects**
- state becomes `Refunded`
- buyer receives the escrow `price`

**Emits**
- `EscrowRefunded(id)`

---

### `disputeEscrow(uint256 id)`
Buyer or seller opens a dispute.

**Requirements**
- escrow exists
- caller is either buyer or seller
- state is `Funded`

**Effects**
- state becomes `Disputed`

**Emits**
- `EscrowDisputed(id)`

---

### `arbiterDecisionRelease(uint256 id)`
Arbiter resolves dispute in favor of the seller.

**Requirements**
- escrow exists
- caller is the arbiter
- state is `Disputed`

**Effects**
- state becomes `Released`
- seller receives the escrow `price`

**Emits**
- `EscrowReleased(id)`

---

### `arbiterDecisionRefund(uint256 id)`
Arbiter resolves dispute in favor of the buyer.

**Requirements**
- escrow exists
- caller is the arbiter
- state is `Disputed`

**Effects**
- state becomes `Refunded`
- buyer receives the escrow `price`

**Emits**
- `EscrowRefunded(id)`

---

## Events

- `EscrowCreated(id, buyer, seller, arbiter)`
- `EscrowAccepted(id, seller)`
- `EscrowCanceled(id, buyer)`
- `EscrowReleased(id)`
- `EscrowRefunded(id)`
- `EscrowDisputed(id)`

---

## Running Locally with Foundry

### Install Foundry
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
