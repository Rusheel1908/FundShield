# FundShield

A hackathon-ready on-chain treasury transparency system built with **Solidity + Foundry**.

`FundShield` now supports a full expense approval workflow with owner and auditor roles, on-chain funds deposits, and automatic suspicious expense flagging.

---

## Project Structure

```
.
├── src/
│   └── FundShield.sol          # Main treasury contract
├── test/
│   └── FundShield.t.sol        # Foundry tests for workflow, roles, and flagging
├── script/
│   └── FundShield.s.sol        # Foundry deployment script
├── foundry.toml
└── README.md
```

> `README (2).md` has been removed to keep the project documentation single-sourced.

---

## What FundShield Does

FundShield lets a team record and manage expense requests on-chain with:

- `depositFunds()` to fund the contract
- `submitExpense()` to request spend approval
- `approveExpense()` / `rejectExpense()` by authorized auditors
- `executeExpense()` to pay approved expenses
- `cancelExpense()` to withdraw pending requests
- automatic `flagged` detection for suspicious requests
- read APIs for pending, flagged, and paginated expenses

This is now a real treasury transparency product, not just a logging demo.

---

## Roles

| Role | Permission |
|---|---|
| `owner` | deployer; can execute approved expenses, update thresholds, and manage auditors |
| `auditor` | can approve or reject expense requests |
| `requester` | any address can submit and cancel pending expenses |

---

## Quick Start

### Build

```bash
forge build
```

### Run tests

```bash
forge test
```

### Format

```bash
forge fmt
```

---

## Local Development (Anvil)

1. Start Anvil:

```bash
anvil
```

2. Deploy locally:

```bash
forge script script/FundShield.s.sol:DeployFundShield \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY> \
  --broadcast
```

3. Deposit funds:

```bash
cast send <CONTRACT_ADDRESS> "depositFunds()" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY> \
  --value 1000000000000000000
```

4. Submit an expense:

```bash
cast send <CONTRACT_ADDRESS> "submitExpense(address,uint256,string,string)" \
  <RECEIVER_ADDRESS> 1000000000000000000 "Q1 payroll" "operations" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY>
```

5. Approve the expense:

```bash
cast send <CONTRACT_ADDRESS> "approveExpense(uint256)" 0 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <OWNER_PRIVATE_KEY>
```

6. Execute the expense:

```bash
cast send <CONTRACT_ADDRESS> "executeExpense(uint256)" 0 \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <OWNER_PRIVATE_KEY>
```

---

## Deploy to Testnet

```bash
export PRIVATE_KEY=0xYourPrivateKey
export RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY

forge script script/FundShield.s.sol:DeployFundShield \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## Contract Interface

### Governance

- `setAuditor(address auditor, bool authorized)`
- `setLargeAmountThreshold(uint256 newThreshold)`

### Funds

- `depositFunds()` payable

### Expense lifecycle

- `submitExpense(address receiver, uint256 amount, string calldata purpose, string calldata category)`
- `approveExpense(uint256 id)`
- `rejectExpense(uint256 id, string calldata reason)`
- `executeExpense(uint256 id)`
- `cancelExpense(uint256 id)`

### Views

- `getExpense(uint256 id)`
- `getExpenses(uint256 start, uint256 count)`
- `getFlaggedExpenses()`
- `getPendingExpenses()`
- `totalExpenses()`

---

## Suspicious Expense Flagging

An expense is flagged when:

- `amount == 0`
- purpose is empty
- `amount > largeAmountThreshold`

This is visible in the expense record and can be used to drive a dashboard or auditor workflow.

---

## Testing

Use Foundry to run the workflow tests:

```bash
forge test
```

The current suite covers:

- expense submission and flagging
- auditor approval and rejection
- execution of approved expenses
- pending expense queries
- owner and auditor access control

---

## Notes

- `README (2).md` has been removed to avoid duplicate documentation.
- Keep `out/`, `cache/`, `broadcast/`, and generated build artifacts out of source control where possible.
