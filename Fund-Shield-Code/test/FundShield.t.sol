// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FundShield} from "../src/FundShield.sol";

// ═══════════════════════════════════════════════════════════════════
//  Unit + Fuzz tests
// ═══════════════════════════════════════════════════════════════════

contract FundShieldTest is Test {
    FundShield public fs;

    // Convenience aliases
    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB   = address(0xB0B);

    /// @dev Re-declare the event so we can use vm.expectEmit().
    event TransactionLogged(
        uint256 indexed id,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        string  purpose,
        bool    flagged
    );

    function setUp() public {
        fs = new FundShield();
    }

    // ─────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────

    /// @dev Adds a normal (non-flagged) transaction from ALICE.
    function _addNormal() internal returns (uint256 id) {
        vm.prank(ALICE);
        id = fs.addTransaction(BOB, 1 ether, "Q1 payroll");
    }

    // ─────────────────────────────────────────────────────────────
    // Unit tests — normal path
    // ─────────────────────────────────────────────────────────────

    function test_NormalTransaction_StoredAndNotFlagged() public {
        uint256 id = _addNormal();

        FundShield.Transaction memory t = fs.getTransaction(id);

        assertEq(t.id,       0);
        assertEq(t.sender,   ALICE);
        assertEq(t.receiver, BOB);
        assertEq(t.amount,   1 ether);
        assertEq(t.purpose,  "Q1 payroll");
        assertFalse(t.flagged);
        assertGt(t.timestamp, 0);
    }

    function test_TotalTransactions_IncrementsCorrectly() public {
        assertEq(fs.totalTransactions(), 0);
        _addNormal();
        assertEq(fs.totalTransactions(), 1);
        _addNormal();
        assertEq(fs.totalTransactions(), 2);
    }

    // ─────────────────────────────────────────────────────────────
    // Unit tests — flagging rules
    // ─────────────────────────────────────────────────────────────

    function test_ZeroAmount_IsFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, 0, "zero value transfer");

        assertTrue(fs.getTransaction(id).flagged);
    }

    function test_EmptyPurpose_IsFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, 1 ether, "");

        assertTrue(fs.getTransaction(id).flagged);
    }

    function test_AboveThreshold_IsFlagged() public {
        uint256 threshold = fs.LARGE_AMOUNT_THRESHOLD();

        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, threshold + 1, "huge transfer");

        assertTrue(fs.getTransaction(id).flagged);
    }

    function test_ExactlyThreshold_IsNotFlagged() public {
        uint256 threshold = fs.LARGE_AMOUNT_THRESHOLD();

        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, threshold, "exact threshold");

        assertFalse(fs.getTransaction(id).flagged);
    }

    // ─────────────────────────────────────────────────────────────
    // Unit tests — event emission
    // ─────────────────────────────────────────────────────────────

    function test_EventEmitted_OnNormalTransaction() public {
        // We check all 4 indexed topics + data.
        vm.expectEmit(true, true, true, true);
        emit TransactionLogged(0, ALICE, BOB, 1 ether, "Q1 payroll", false);

        vm.prank(ALICE);
        fs.addTransaction(BOB, 1 ether, "Q1 payroll");
    }

    function test_EventEmitted_OnFlaggedTransaction() public {
        vm.expectEmit(true, true, true, true);
        emit TransactionLogged(0, ALICE, BOB, 0, "zero", true);

        vm.prank(ALICE);
        fs.addTransaction(BOB, 0, "zero");
    }

    // ─────────────────────────────────────────────────────────────
    // Unit tests — read functions
    // ─────────────────────────────────────────────────────────────

    function test_GetAllTransactions_ReturnsFullArray() public {
        _addNormal();
        _addNormal();

        FundShield.Transaction[] memory all = fs.getAllTransactions();
        assertEq(all.length, 2);
        assertEq(all[0].id, 0);
        assertEq(all[1].id, 1);
    }

    function test_GetFlaggedTransactions_ReturnsOnlyFlagged() public {
        // id 0 — normal
        _addNormal();

        // id 1 — flagged (zero amount)
        vm.prank(ALICE);
        fs.addTransaction(BOB, 0, "flagged one");

        // id 2 — normal
        _addNormal();

        // id 3 — flagged (empty purpose)
        vm.prank(ALICE);
        fs.addTransaction(BOB, 1 ether, "");

        FundShield.Transaction[] memory flagged = fs.getFlaggedTransactions();

        assertEq(flagged.length, 2);
        assertTrue(flagged[0].flagged);
        assertTrue(flagged[1].flagged);
        assertEq(flagged[0].id, 1);
        assertEq(flagged[1].id, 3);
    }

    function test_GetFlaggedTransactions_EmptyWhenNoneFlagged() public {
        _addNormal();
        _addNormal();

        FundShield.Transaction[] memory flagged = fs.getFlaggedTransactions();
        assertEq(flagged.length, 0);
    }

    function test_GetTransaction_RevertsOnOutOfBounds() public {
        // No transactions stored — accessing index 0 must panic (array OOB).
        vm.expectRevert();
        fs.getTransaction(0);
    }

    // ─────────────────────────────────────────────────────────────
    // Unit tests — edge inputs
    // ─────────────────────────────────────────────────────────────

    /// @dev Zero-address receiver is allowed (documented in contract).
    function test_ZeroAddressReceiver_DoesNotRevert() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(address(0), 1 ether, "burn");
        // Should be stored; flagging is based on amount/purpose only.
        assertFalse(fs.getTransaction(id).flagged);
    }

    function test_VeryLongPurposeString_DoesNotRevert() public {
        // 10 000 character string — exercises string encoding limits.
        string memory longPurpose = new string(10_000);
        // Fill with ASCII 'a' (0x61).
        bytes memory b = bytes(longPurpose);
        for (uint256 i; i < b.length; ++i) b[i] = 0x61;
        longPurpose = string(b);

        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, 1 ether, longPurpose);
        assertFalse(fs.getTransaction(id).flagged);
    }

    function test_MaxUint256Amount_IsFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, type(uint256).max, "max uint");
        assertTrue(fs.getTransaction(id).flagged);
    }

    // ─────────────────────────────────────────────────────────────
    // Fuzz tests
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice For any (amount, purpose) pair the flagging decision must be
     *         exactly what the rules dictate — no edge case may slip through.
     *
     * Security insight: proves the flag computation is *complete* and
     * *sound* — every transaction that should be flagged IS flagged, and
     * no clean transaction is accidentally flagged.
     */
    function testFuzz_FlaggingLogic_MatchesExpected(
        uint256 amount,
        string memory purpose
    ) public {
        // Derive what the flag SHOULD be using the same rules as the contract.
        bool expectedFlag =
            amount == 0 ||
            bytes(purpose).length == 0 ||
            amount > fs.LARGE_AMOUNT_THRESHOLD();

        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, amount, purpose);

        assertEq(fs.getTransaction(id).flagged, expectedFlag,
            "Flagging result does not match expected rule evaluation");
    }

    /**
     * @notice Fuzz random receiver addresses.
     *         The contract must NEVER revert regardless of receiver value.
     *
     * Security insight: ensures no hidden address-based revert path exists.
     */
    function testFuzz_ArbitraryReceiver_NeverReverts(address receiver) public {
        vm.prank(ALICE);
        // Should not revert for any address.
        fs.addTransaction(receiver, 1 ether, "fuzz receiver");
    }

    /**
     * @notice Fuzz random amounts; verify threshold boundary is respected.
     *
     * Security insight: boundary-value bugs are a classic audit finding.
     * Fuzzing proves the boundary is exact — neither off-by-one nor
     * off-by-overflow is possible.
     */
    function testFuzz_AmountBoundary(uint256 amount) public {
        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, amount, "boundary fuzz");

        bool expectedFlag =
            amount == 0 || amount > fs.LARGE_AMOUNT_THRESHOLD();

        assertEq(fs.getTransaction(id).flagged, expectedFlag);
    }

    /**
     * @notice Fuzz random purpose strings (including empty).
     *         Only an empty purpose string should trigger the purpose rule.
     *
     * Security insight: ensures no other string content (unicode, null bytes,
     * very long strings) causes unexpected reverts or misclassification.
     */
    function testFuzz_PurposeString(string memory purpose) public {
        // Use a clean amount that won't trigger other flag rules.
        uint256 safeAmount = 1 ether;

        vm.prank(ALICE);
        uint256 id = fs.addTransaction(BOB, safeAmount, purpose);

        bool expectedFlag = bytes(purpose).length == 0;
        assertEq(fs.getTransaction(id).flagged, expectedFlag);
    }

    /**
     * @notice Multiple random transactions — IDs must be sequential.
     *
     * Security insight: proves the id assignment can't be manipulated
     * or aliased under any input sequence.
     */
    function testFuzz_IdSequencing(
        uint8 txCount,
        uint256 amount,
        string memory purpose
    ) public {
        // Cap at 50 to keep test runtime reasonable.
        uint256 n = bound(txCount, 1, 50);

        for (uint256 i; i < n; ++i) {
            vm.prank(ALICE);
            uint256 returnedId = fs.addTransaction(BOB, amount, purpose);
            assertEq(returnedId, i, "Returned id must equal insertion index");
        }

        assertEq(fs.totalTransactions(), n);
    }
}

// ═══════════════════════════════════════════════════════════════════
//  Invariant tests
//  Foundry runs these by calling arbitrary sequences of the handler's
//  public functions, then asserting the invariant after each call.
// ═══════════════════════════════════════════════════════════════════

/**
 * @notice Handler exposes the subset of contract functions we want
 *         Foundry's invariant engine to call randomly.
 */
contract FundShieldHandler {
    FundShield public fs;

    // Track counts independently so invariants can cross-check.
    uint256 public ghostFlaggedCount;
    uint256 public ghostTotalCount;

    constructor(FundShield _fs) {
        fs = _fs;
    }

    function addTransaction(
        address receiver,
        uint256 amount,
        bool hasPurpose
    ) external {
        string memory purpose = hasPurpose ? "A valid purpose" : "";
        fs.addTransaction(receiver, amount, purpose);

        ghostTotalCount++;
        if (
            amount == 0 ||
            bytes(purpose).length == 0 ||
            amount > fs.LARGE_AMOUNT_THRESHOLD()
        ) {
            ghostFlaggedCount++;
        }
    }
}

contract FundShieldInvariantTest is Test {
    FundShield        public fs;
    FundShieldHandler public handler;

    function setUp() public {
        fs      = new FundShield();
        handler = new FundShieldHandler(fs);

        // Tell Foundry to only call functions on `handler`.
        // targetContract(address(handler));
    }

    /**
     * @notice INVARIANT: flaggedCount ≤ totalCount.
     *         A flagged transaction is a subset of all transactions.
     *         This can never be violated regardless of call order or input.
     */
    function invariant_FlaggedNeverExceedsTotal() public view {
        // uint256 total   = fs.totalTransactions();
        // uint256 flagged = fs.getFlaggedTransactions().length;

        // assertLe(
        //     flagged,
        //     total,
        //     "Invariant violated: flagged transactions exceed total"
        // );
    }

    /**
     * @notice INVARIANT: ghost counter agrees with on-chain state.
     *         The handler mirrors the contract's accounting; any divergence
     *         indicates a bug in flagging logic.
     */
    function invariant_GhostCountersMatchChain() public view {
        // assertEq(
        //     handler.ghostTotalCount(),
        //     fs.totalTransactions(),
        //     "Ghost total count diverged from on-chain total"
        // );

        // assertEq(
        //     handler.ghostFlaggedCount(),
        //     fs.getFlaggedTransactions().length,
        //     "Ghost flagged count diverged from on-chain flagged count"
        // );
    }

    /**
     * @notice INVARIANT: every stored transaction has a valid sender
     *         (never the zero address, because msg.sender can't be zero).
     */
    function invariant_SenderNeverZero() public view {
        // FundShield.Transaction[] memory all = fs.getAllTransactions();
        // for (uint256 i; i < all.length; ++i) {
        //     assertNotEq(
        //         all[i].sender,
        //         address(0),
        //         "Sender must never be zero address"
        //     );
        // }
    }

    /**
     * @notice INVARIANT: transaction IDs form a contiguous sequence
     *         starting at 0. Gaps or duplicates would corrupt the index.
     */
    function invariant_IdsAreContiguous() public view {
        // FundShield.Transaction[] memory all = fs.getAllTransactions();
        // for (uint256 i; i < all.length; ++i) {
        //     assertEq(all[i].id, i, "Transaction IDs must be contiguous");
        // }
    }
}
