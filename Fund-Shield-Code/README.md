# FundShield

On-chain public fund transparency system built with **Solidity + Foundry + ethers.js v6**.

🌐 **Live Demo:** https://fund-shield.netlify.app

Live on Sepolia: `0x03f50393d76E84D6f7C150C4e00836D1C3470D53`

---

## Features

| # | Feature | Description |
|---|---|---|
| 1 | **Chainlink USD Fraud Detection** | Expenses above $10,000 (live ETH/USD price feed) are automatically flagged |
| 2 | **Multi-Sig Quorum Approval** | Configurable number of auditor signatures required before any expense is approved |
| 3 | **48h Time-Lock on Flagged Expenses** | Flagged expenses cannot be executed until 48 hours after approval — prevents rushed fraud |
| 4 | **Category Spending Caps** | Owner sets per-category ETH budgets; over-budget submissions are flagged at submit time |
| 5 | **Velocity / Repeat-Receiver Flagging** | More than 3 payments to the same address in 7 days triggers automatic flagging |
| 6 | **Role-Based Access Control** | Owner, auditor, and public roles with on-chain enforcement via custom errors |
| 7 | **Paginated Expense Ledger** | `getExpenses(start, count)` for efficient dashboard reads without N+1 RPC calls |

---

## Project Structure

```
.
├── src/
│   └── FundShield.sol          # Main treasury contract (426 lines)
├── test/
│   └── FundShield.t.sol        # 35 Foundry tests — all passing
├── script/
│   └── FundShield.s.sol        # Deployment script
├── Frontend/
│   └── index.html              # Single-file SPA (vanilla JS + ethers.js v6)
├── foundry.toml
└── README.md
```

---

## Roles

| Role | Permission |
|---|---|
| `owner` | Deployer. Can execute approved expenses, update thresholds, manage auditors, set quorum |
| `auditor` | Can approve or reject expense requests |
| `anyone` | Can submit expenses, cancel their own pending requests, read all data |

---

## Quick Start

### Build

```bash
forge build
```

### Run tests (35 tests)

```bash
forge test -vvv
```

### Format

```bash
forge fmt
```

---

## Deployed Contract — Sepolia

| Field | Value |
|---|---|
| Address | `0x03f50393d76E84D6f7C150C4e00836D1C3470D53` |
| Network | Ethereum Sepolia testnet |
| ETH/USD Feed | `0x694AA1769357215DE4FAC081bf1f309aDC325306` (Chainlink) |
| Default quorum | 1 auditor signature |
| Default flag threshold | $10,000 USD |
| Time-lock delay | 48 hours |
| Velocity window | 7 days / 3 payments |

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
  --value 1ether
```

4. Submit an expense:

```bash
cast send <CONTRACT_ADDRESS> "submitExpense(address,uint256,string,string)" \
  <RECEIVER_ADDRESS> 1ether "Q1 payroll" "operations" \
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
- `setRequiredApprovals(uint256 n)`
- `setLargeAmountThresholdUSD(uint256 newThreshold)`
- `setCategoryBudget(string calldata category, uint256 budget)`
- `setVelocityThreshold(uint256 n)`
- `setTimeLockDelay(uint256 seconds_)`

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
- `getExpenses(uint256 start, uint256 count)` — paginated batch read
- `getFlaggedExpenses()`
- `getPendingExpenses()`
- `totalExpenses()`
- `hasApproved(uint256 id, address auditor)`
- `executeAfter(uint256 id)`
- `getCategoryInfo(string calldata category)` → `(budget, spent, remaining)`
- `getLatestETHPrice()` — Chainlink feed
- `getAmountInUSD(uint256 weiAmount)` — on-chain USD conversion

---

## Suspicious Expense Flagging

An expense is flagged automatically when **any** of these conditions fire at submit time:

| Condition | Trigger |
|---|---|
| Zero amount | `amount == 0` |
| Empty purpose | `bytes(purpose).length == 0` |
| High USD value | `getAmountInUSD(amount) > largeAmountThresholdUSD` (Chainlink) |
| Over category budget | `categorySpent[cat] + amount > categoryBudget[cat]` |
| Velocity breach | receiver received ≥ `velocityThreshold` payments in the last 7 days |

Flagged expenses are time-locked for 48 hours after approval before execution is permitted.

---

## Testing

```bash
forge test -vvv
```

35 tests covering:

- Price feed integration and USD conversion
- Expense submission, flagging (zero, empty purpose, high USD, over-budget, velocity)
- Auditor approval, rejection, cancellation
- Multi-sig: quorum enforcement, double-sign prevention, `hasApproved` tracking
- Time-lock: immediate execution for clean, 48h lock for flagged
- Category budget: set/read, over-budget flag, spent tracking on execution
- Velocity window: below threshold, above threshold, 7-day reset
- Access control: `OnlyAuditor`, `InvalidQuorum`, `AlreadySigned`, `TimeLockActive`
- Paginated reads: `getPendingExpenses`

---

## Frontend

Single-file SPA at `Frontend/index.html`. No build step — open directly in browser or serve statically.

- Auto-detects wallet role (admin/auditor/public) on MetaMask connect
- Public read-only mode via Sepolia JSON-RPC (no wallet required)
- Demo mode with pre-seeded data for judging without MetaMask
- Batched RPC: 2 parallel rounds instead of N sequential calls
- CSV export of full expense ledger
