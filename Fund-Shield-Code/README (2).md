# ⬡ FundShield

A trust-minimised, fully on-chain fund transparency system built with **Solidity + Foundry**. No admin. No upgradeable proxy. Every transaction is permanently recorded and automatically flagged when it matches any suspicious-activity rule.

---

## Table of Contents

1. [Project Structure](#project-structure)
2. [How It Works](#how-it-works)
3. [Prerequisites](#prerequisites)
4. [Foundry Setup](#foundry-setup)
5. [Local Development (Anvil)](#local-development-anvil)
6. [Deploy to a Testnet](#deploy-to-a-testnet)
7. [Running Tests](#running-tests)
8. [Writing Tests with Foundry](#writing-tests-with-foundry)
9. [Flagging Rules](#flagging-rules)
10. [Contract Interface](#contract-interface)
11. [Known Limitations & TODOs](#known-limitations--todos)

---

## Project Structure

```
.
├── src/
│   └── FundShield.sol          # Main contract
├── test/
│   └── FundShield.t.sol        # Foundry unit, fuzz & invariant tests
├── script/
│   └── FundShield.s.sol        # Foundry deploy script
├── foundry.toml
└── README.md
```

> If you haven't scaffolded the Foundry project yet, do it first — see [Foundry Setup](#foundry-setup).

---

## How It Works

| Role | Responsibility |
|---|---|
| **Submitter** | Calls `addTransaction()` with a receiver, amount (in wei), and a human-readable purpose |
| **Auditor / Dashboard** | Calls `getFlaggedTransactions()` to pull all suspicious records for review |
| **Anyone** | Calls `getAllTransactions()` or `getTransaction(id)` to inspect the full on-chain history |

**Flow:**
```
addTransaction(receiver, amount, purpose)
    │
    ├─► _shouldFlag() evaluates all rules
    │       ├─ amount == 0          → flagged = true
    │       ├─ purpose is empty     → flagged = true
    │       └─ amount > 1 000 ETH  → flagged = true
    │
    ├─► Transaction stored permanently in _transactions[]
    │
    └─► TransactionLogged event emitted (id, sender, receiver, amount, purpose, flagged)
```

**Flagging rules (any one suffices to flag):**

| # | Rule | Rationale |
|---|---|---|
| 1 | `amount == 0` | Zero-value transfer is meaningless or suspicious |
| 2 | `purpose` is empty | Undocumented transfer is a transparency red flag |
| 3 | `amount > LARGE_AMOUNT_THRESHOLD` (1 000 ETH) | Unusually large single transfer |

> **Note:** Zero-address receivers are intentionally **allowed** and not flagged. This supports burn-style transfers and donations. Use a non-empty `purpose` to document the intent.

---

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| [Foundry](https://book.getfoundry.sh/getting-started/installation) | latest | `curl -L https://foundry.paradigm.xyz \| bash && foundryup` |
| [Node.js](https://nodejs.org) | ≥ 18 | For a local HTTP server only (if building a frontend) |
| [MetaMask](https://metamask.io) | any | Browser extension (if integrating a frontend) |
| Git | any | Pre-installed on most systems |

Verify Foundry is installed:
```bash
forge --version    # e.g. forge 0.2.0
anvil --version
cast --version
```

---

## Foundry Setup

### 1. Initialise the project

```bash
# From your project root
forge init --no-commit .
```

This creates `src/`, `test/`, `script/`, `lib/`, and `foundry.toml`.

### 2. Move the contracts into place

```bash
cp FundShield.sol    src/FundShield.sol
cp FundShield.t.sol  test/FundShield.t.sol
cp FundShield.s.sol  script/FundShield.s.sol
```

### 3. Configure `foundry.toml`

```toml
[profile.default]
src     = "src"
out     = "out"
libs    = ["lib"]
solc    = "0.8.20"

# Optional — speeds up compilation
optimizer        = true
optimizer_runs   = 200

# Gas reporting in tests
gas_reports = ["FundShield"]
```

### 4. Compile

```bash
forge build
```

Expected output: `Compiler run successful!` with artefacts written to `out/`.

---

## Local Development (Anvil)

Anvil is Foundry's local testnet — it mines a block per transaction and gives you 10 pre-funded accounts.

### 1. Start Anvil

```bash
anvil
```

Copy one of the printed private keys — you'll need it for deploying and for testing in MetaMask.

### 2. Deploy to Anvil

```bash
forge script script/FundShield.s.sol:DeployFundShield \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY_0> \
  --broadcast
```

The deployed address is printed to stdout — copy it, you will need it to interact with the contract.

### 3. Interact using Cast

Record a normal transaction:
```bash
cast send <CONTRACT_ADDRESS> \
  "addTransaction(address,uint256,string)" \
  <RECEIVER_ADDRESS> 1000000000000000000 "Q1 payroll" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY_0>
```

Record a flagged transaction (zero amount):
```bash
cast send <CONTRACT_ADDRESS> \
  "addTransaction(address,uint256,string)" \
  <RECEIVER_ADDRESS> 0 "test zero" \
  --rpc-url http://127.0.0.1:8545 \
  --private-key <ANVIL_PRIVATE_KEY_0>
```

Read all transactions:
```bash
cast call <CONTRACT_ADDRESS> "getAllTransactions()" \
  --rpc-url http://127.0.0.1:8545
```

Read only flagged transactions:
```bash
cast call <CONTRACT_ADDRESS> "getFlaggedTransactions()" \
  --rpc-url http://127.0.0.1:8545
```

Get the total transaction count:
```bash
cast call <CONTRACT_ADDRESS> "totalTransactions()" \
  --rpc-url http://127.0.0.1:8545
```

Get a single transaction by ID:
```bash
cast call <CONTRACT_ADDRESS> "getTransaction(uint256)" 0 \
  --rpc-url http://127.0.0.1:8545
```

---

## Deploy to a Testnet

Use **Sepolia** (recommended) or any EVM-compatible testnet.

```bash
# Export your keys — never hardcode them
export PRIVATE_KEY=0xYourPrivateKey
export RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY   # or Alchemy

forge script script/FundShield.s.sol:DeployFundShield \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \                          # optional: verifies on Etherscan
  --etherscan-api-key $ETHERSCAN_KEY
```

> **Tip:** Use a `.env` file and `source .env` — never commit private keys.

The deploy script also logs the `LARGE_AMOUNT_THRESHOLD` constant to confirm the deployment parameters are correct:
```
FundShield deployed at: 0xAbc123...
LARGE_AMOUNT_THRESHOLD: 1000000000000000000000
```

---

## Running Tests

### Quick test run

```bash
forge test
```

### Verbose output (shows logs and traces)

```bash
forge test -vvv
```

### Run a single test file

```bash
forge test --match-path test/FundShield.t.sol -vvv
```

### Run a single test function

```bash
forge test --match-test test_ZeroAmount_IsFlagged -vvv
```

### Run only fuzz tests

```bash
forge test --match-test testFuzz -vvv
```

### Run only invariant tests

```bash
forge test --match-contract FundShieldInvariantTest -vvv
```

### Gas report

```bash
forge test --gas-report
```

### Gas snapshot (saves a baseline for future comparison)

```bash
forge snapshot
```

---

## Writing Tests with Foundry

The test file `test/FundShield.t.sol` is split into three layers — unit, fuzz, and invariant. Here is a summary of what each covers and how to extend them.

### Unit Tests

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FundShield} from "../src/FundShield.sol";

contract FundShieldTest is Test {
    FundShield public fs;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB   = address(0xB0B);

    function setUp() public {
        fs = new FundShield();
    }

    // Happy path — normal transaction stored and not flagged
    function test_NormalTransaction_StoredAndNotFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, 1 ether, "Q1 payroll");

        FundShield.Transaction memory t = fs.getTransaction(id);

        assertEq(t.id,       0);
        assertEq(t.sender,   ALICE);
        assertEq(t.receiver, BOB);
        assertEq(t.amount,   1 ether);
        assertEq(t.purpose,  "Q1 payroll");
        assertFalse(t.flagged);
        assertGt(t.timestamp, 0);
    }

    // Flagging rule 1 — zero amount
    function test_ZeroAmount_IsFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, 0, "zero value");
        assertTrue(fs.getTransaction(id).flagged);
    }

    // Flagging rule 2 — empty purpose
    function test_EmptyPurpose_IsFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, 1 ether, "");
        assertTrue(fs.getTransaction(id).flagged);
    }

    // Flagging rule 3 — above threshold
    function test_AboveThreshold_IsFlagged() public {
        uint256 threshold = fs.LARGE_AMOUNT_THRESHOLD();
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, threshold + 1, "huge transfer");
        assertTrue(fs.getTransaction(id).flagged);
    }

    // Boundary — exactly at threshold is NOT flagged
    function test_ExactlyThreshold_IsNotFlagged() public {
        uint256 threshold = fs.LARGE_AMOUNT_THRESHOLD();
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, threshold, "exact threshold");
        assertFalse(fs.getTransaction(id).flagged);
    }

    // Read — getFlaggedTransactions returns only flagged records
    function test_GetFlaggedTransactions_ReturnsOnlyFlagged() public {
        vm.prank(ALICE);
        fs.addTransaction(BOB, 1 ether, "normal");       // id 0 — clean

        vm.prank(ALICE);
        fs.addTransaction(BOB, 0, "flagged one");        // id 1 — flagged

        vm.prank(ALICE);
        fs.addTransaction(BOB, 1 ether, "normal again"); // id 2 — clean

        vm.prank(ALICE);
        fs.addTransaction(BOB, 1 ether, "");             // id 3 — flagged

        FundShield.Transaction[] memory flagged = fs.getFlaggedTransactions();
        assertEq(flagged.length, 2);
        assertEq(flagged[0].id, 1);
        assertEq(flagged[1].id, 3);
    }

    // Edge — zero-address receiver is allowed and not flagged on its own
    function test_ZeroAddressReceiver_DoesNotRevert() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(address(0), 1 ether, "burn");
        assertFalse(fs.getTransaction(id).flagged);
    }

    // Edge — OOB access reverts
    function test_GetTransaction_RevertsOnOutOfBounds() public {
        vm.expectRevert();
        fs.getTransaction(0);
    }
}
```

### Fuzz Tests

Foundry runs fuzz tests with random inputs automatically. Extend them by adding more input parameters or tightening the `assume` / `bound` guards.

```solidity
// Proves flagging is complete and sound for ALL possible (amount, purpose) pairs
function testFuzz_FlaggingLogic_MatchesExpected(
    uint256 amount,
    string memory purpose
) public {
    bool expectedFlag =
        amount == 0 ||
        bytes(purpose).length == 0 ||
        amount > fs.LARGE_AMOUNT_THRESHOLD();

    vm.prank(ALICE);
    uint256 id = fs.addTransaction(BOB, amount, purpose);

    assertEq(fs.getTransaction(id).flagged, expectedFlag,
        "Flagging result does not match expected rule evaluation");
}

// Proves the contract never reverts for any receiver address
function testFuzz_ArbitraryReceiver_NeverReverts(address receiver) public {
    vm.prank(ALICE);
    fs.addTransaction(receiver, 1 ether, "fuzz receiver");
}

// Proves ID sequencing is always correct regardless of input sequence
function testFuzz_IdSequencing(
    uint8 txCount,
    uint256 amount,
    string memory purpose
) public {
    uint256 n = bound(txCount, 1, 50);
    for (uint256 i; i < n; ++i) {
        vm.prank(ALICE);
        uint256 returnedId = fs.addTransaction(BOB, amount, purpose);
        assertEq(returnedId, i, "Returned id must equal insertion index");
    }
    assertEq(fs.totalTransactions(), n);
}
```

Configure fuzz run count in `foundry.toml`:
```toml
[fuzz]
runs = 1000
```

### Invariant Tests

Invariant tests use a **handler contract** that Foundry calls randomly. The invariants are asserted after every call sequence.

```solidity
// INVARIANT: flagged count is always ≤ total count
function invariant_FlaggedNeverExceedsTotal() public view {
    assertLe(
        fs.getFlaggedTransactions().length,
        fs.totalTransactions(),
        "Invariant violated: flagged transactions exceed total"
    );
}

// INVARIANT: ghost counters in the handler always agree with on-chain state
function invariant_GhostCountersMatchChain() public view {
    assertEq(handler.ghostTotalCount(),   fs.totalTransactions());
    assertEq(handler.ghostFlaggedCount(), fs.getFlaggedTransactions().length);
}

// INVARIANT: sender is never the zero address
function invariant_SenderNeverZero() public view {
    FundShield.Transaction[] memory all = fs.getAllTransactions();
    for (uint256 i; i < all.length; ++i) {
        assertNotEq(all[i].sender, address(0));
    }
}

// INVARIANT: IDs are always contiguous starting at 0
function invariant_IdsAreContiguous() public view {
    FundShield.Transaction[] memory all = fs.getAllTransactions();
    for (uint256 i; i < all.length; ++i) {
        assertEq(all[i].id, i);
    }
}
```

Configure invariant run depth in `foundry.toml`:
```toml
[invariant]
runs  = 256
depth = 128
```

Run all tests:
```bash
forge test --match-path test/FundShield.t.sol -vvv
```

---

## Flagging Rules

A transaction is automatically flagged when **any** of the following conditions fire:

| # | Rule | Condition | Rationale |
|---|---|---|---|
| 1 | Zero-value transfer | `amount == 0` | Meaningless or potentially obfuscating transfer |
| 2 | Undocumented transfer | `bytes(purpose).length == 0` | No documentation = transparency violation |
| 3 | Unusually large transfer | `amount > 1_000 ether` | Single transfer unlikely for a typical operational fund |

> `LARGE_AMOUNT_THRESHOLD` is `1_000 ether` (in wei). Adjust it to your organisation's risk appetite before mainnet use.

---

## Contract Interface

### Write

| Function | Parameters | Returns | Description |
|---|---|---|---|
| `addTransaction` | `address receiver`, `uint256 amount`, `string purpose` | `uint256 id` | Records a new transaction and applies all flagging rules. Emits `TransactionLogged`. |

### Read

| Function | Parameters | Returns | Description |
|---|---|---|---|
| `getTransaction` | `uint256 id` | `Transaction` | Returns the transaction at the given index. Reverts with array-OOB panic if `id >= totalTransactions()`. |
| `getAllTransactions` | — | `Transaction[]` | Returns the full transaction history in insertion order. |
| `getFlaggedTransactions` | — | `Transaction[]` | Returns only transactions where `flagged == true`. |
| `totalTransactions` | — | `uint256` | Returns the total number of recorded transactions. |
| `LARGE_AMOUNT_THRESHOLD` | — | `uint256` | Returns the large-amount flag threshold (1 000 ETH in wei). |

### Transaction Struct

```solidity
struct Transaction {
    uint256 id;         // Auto-incrementing index (0-based)
    address sender;     // EOA or contract that called addTransaction()
    address receiver;   // Intended destination of the funds
    uint256 amount;     // Value in wei
    string  purpose;    // Human-readable description of the transfer
    bool    flagged;    // True when any suspicious-activity rule fires
    uint256 timestamp;  // Block timestamp at record time (seconds since epoch)
}
```

### Events

```solidity
event TransactionLogged(
    uint256 indexed id,
    address indexed sender,
    address indexed receiver,
    uint256 amount,
    string  purpose,
    bool    flagged
);
```

Emitted on every call to `addTransaction`. All three indexed fields enable efficient log filtering by sender, receiver, or transaction id.

---

## Known Limitations & TODOs

- **No access control** — anyone can call `addTransaction()`. For a production system, consider restricting submission to authorised addresses (e.g. a multisig or role-based access control via OpenZeppelin `AccessControl`).
- **`getAllTransactions()` is unbounded** — returning a full dynamic struct array is fine for a demo or dashboard read, but will hit gas limits if the transaction count grows very large. Add pagination (e.g. `getTransactions(uint256 offset, uint256 limit)`) before mainnet use.
- **`getFlaggedTransactions()` is O(n) with two passes** — acceptable at demo scale, but consider maintaining a separate `_flaggedIds` array to make this O(flagged) instead of O(total).
- **No IPFS integration for `purpose`** — purposes are stored as plain on-chain strings. For longer documentation, consider storing an IPFS CID as the purpose string and integrating [web3.storage](https://web3.storage) or [Pinata](https://pinata.cloud) in your frontend.
- **`LARGE_AMOUNT_THRESHOLD` is a compile-time constant** — it cannot be changed without redeploying. Consider making it a governance-controlled state variable for real-world use.
- **No events indexed for a frontend** — consider adding a subgraph (The Graph) or using `eth_getLogs` polling to power a live dashboard from the `TransactionLogged` event.
- **Timestamp can be manipulated by validators** — `block.timestamp` is accurate to within ~15 seconds. Do not use it for precision time logic; it is fine for audit trail purposes only.
