// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FundShield} from "../src/FundShield.sol";

contract MockV3Aggregator {
    int256 private _price;

    constructor(int256 initialPrice) {
        _price = initialPrice;
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }

    function decimals() external pure returns (uint8) {
        return 8;
    }

    function updatePrice(int256 newPrice) external {
        _price = newPrice;
    }
}

contract FundShieldTest is Test {
    FundShield public fs;
    MockV3Aggregator internal mockFeed;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    // Mock price: $3,000/ETH (8 decimals)
    int256 internal constant MOCK_ETH_PRICE = 3_000e8;

    function setUp() public {
        mockFeed = new MockV3Aggregator(MOCK_ETH_PRICE);
        fs = new FundShield(address(mockFeed));
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 10 ether);
    }

    function test_OwnerIsDeployerAndAuditor() public view {
        assertEq(fs.owner(), address(this));
        assertTrue(fs.auditors(address(this)));
        assertEq(fs.requiredApprovals(), 1);
    }

    function test_PriceFeedIsSet() public view {
        assertEq(address(fs.priceFeed()), address(mockFeed));
    }

    function test_DefaultThresholdIsCorrect() public view {
        assertEq(fs.largeAmountThresholdUSD(), 10_000e8); // $10,000
    }

    function test_GetLatestETHPrice() public view {
        assertEq(fs.getLatestETHPrice(), uint256(MOCK_ETH_PRICE));
    }

    function test_GetAmountInUSD() public view {
        // 1 ETH at $3,000 = $3,000 (8 decimals)
        assertEq(fs.getAmountInUSD(1 ether), 3_000e8);
    }

    function test_DepositFunds_IncreasesBalance() public {
        vm.prank(ALICE);
        fs.depositFunds{value: 1 ether}();

        assertEq(address(fs).balance, 1 ether);
    }

    function test_SubmitExpense_StoresPendingExpense() public {
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "Q1 payroll", "operations");

        FundShield.Expense memory expense = fs.getExpense(id);

        assertEq(expense.id, 0);
        assertEq(expense.requester, ALICE);
        assertEq(expense.receiver, BOB);
        assertEq(expense.amount, 1 ether);
        assertEq(expense.purpose, "Q1 payroll");
        assertEq(expense.category, "operations");
        assertEq(uint256(expense.status), uint256(FundShield.Status.Pending));
        assertFalse(expense.flagged); // 1 ETH = $3,000 < $10,000 threshold
    }

    function test_SubmitExpense_ZeroAmountIsFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 0, "zero transfer", "audit");

        assertTrue(fs.getExpense(id).flagged);
    }

    function test_SubmitExpense_EmptyPurposeIsFlagged() public {
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "", "audit");

        assertTrue(fs.getExpense(id).flagged);
    }

    function test_SubmitExpense_AboveThresholdUSDIsFlagged() public {
        // 4 ETH × $3,000/ETH = $12,000 > $10,000 threshold → should flag
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 4 ether, "big spend", "capital");

        assertTrue(fs.getExpense(id).flagged);
    }

    function test_SubmitExpense_BelowThresholdUSDNotFlagged() public {
        // 3 ETH × $3,000/ETH = $9,000 < $10,000 threshold → should not flag
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 3 ether, "vendor payment", "operations");

        assertFalse(fs.getExpense(id).flagged);
    }

    function test_SubmitExpense_PriceFeedUnavailableSkipsUSDCheck() public {
        // Price of 0 means feed unavailable — large amount should NOT be flagged (graceful degradation)
        mockFeed.updatePrice(0);

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 100 ether, "large payment", "operations");

        assertFalse(fs.getExpense(id).flagged);
    }

    function test_ApproveAndExecuteExpense() public {
        vm.prank(ALICE);
        fs.depositFunds{value: 2 ether}();

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");

        fs.approveExpense(id);
        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Approved));

        fs.executeExpense(id);
        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Executed));
        assertEq(address(fs).balance, 1 ether);
    }

    function test_RejectExpense() public {
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");

        fs.rejectExpense(id, "policy mismatch");

        FundShield.Expense memory expense = fs.getExpense(id);
        assertEq(uint256(expense.status), uint256(FundShield.Status.Rejected));
        assertEq(expense.rejectReason, "policy mismatch");
        assertEq(expense.approver, address(this));
    }

    function test_CancelExpense() public {
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");

        vm.prank(ALICE);
        fs.cancelExpense(id);

        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Cancelled));
    }

    function test_SetAuditorByOwner() public {
        fs.setAuditor(ALICE, true);
        assertTrue(fs.auditors(ALICE));
    }

    function test_SetLargeAmountThresholdUSD() public {
        fs.setLargeAmountThresholdUSD(50_000e8); // $50,000
        assertEq(fs.largeAmountThresholdUSD(), 50_000e8);
    }

    function test_MultiSig_SingleAuditorDefaultWorks() public {
        // requiredApprovals=1 (default): one approval is enough
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");

        fs.approveExpense(id); // owner is also auditor
        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Approved));
        assertEq(fs.getExpense(id).approvalCount, 1);
    }

    function test_MultiSig_RequiresTwoApprovals() public {
        address CAROL = address(0xCA401);
        fs.setAuditor(ALICE, true);
        fs.setAuditor(CAROL, true);
        fs.setRequiredApprovals(2);

        vm.prank(BOB);
        uint256 id = fs.submitExpense(address(0xDEAD), 1 ether, "pay vendor", "operations");

        // First signature — still Pending
        vm.prank(ALICE);
        fs.approveExpense(id);
        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Pending));
        assertEq(fs.getExpense(id).approvalCount, 1);

        // Second signature — now Approved
        vm.prank(CAROL);
        fs.approveExpense(id);
        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Approved));
        assertEq(fs.getExpense(id).approvalCount, 2);
    }

    function test_MultiSig_CannotSignTwice() public {
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");

        fs.approveExpense(id);

        vm.expectRevert(abi.encodeWithSelector(FundShield.AlreadySigned.selector, id, address(this)));
        fs.approveExpense(id);
    }

    function test_MultiSig_HasApprovedTracksCorrectly() public {
        fs.setAuditor(ALICE, true);
        fs.setRequiredApprovals(2);

        vm.prank(BOB);
        uint256 id = fs.submitExpense(address(0xDEAD), 1 ether, "pay vendor", "operations");

        assertFalse(fs.hasApproved(id, address(this)));
        fs.approveExpense(id);
        assertTrue(fs.hasApproved(id, address(this)));
        assertFalse(fs.hasApproved(id, ALICE));
    }

    function test_SetRequiredApprovals_ZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(FundShield.InvalidQuorum.selector, 0));
        fs.setRequiredApprovals(0);
    }

    // ─── Category spending caps ─────────────────────────────────

    // ─── Time-lock ──────────────────────────────────────────────

    function test_TimeLock_CleanExpenseExecutesImmediately() public {
        vm.prank(ALICE);
        fs.depositFunds{value: 2 ether}();

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");
        fs.approveExpense(id);

        // Not flagged → no time-lock → should execute immediately
        assertEq(fs.executeAfter(id), 0);
        fs.executeExpense(id);
        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Executed));
    }

    function test_TimeLock_FlaggedExpenseLockedFor48h() public {
        vm.prank(ALICE);
        fs.depositFunds{value: 10 ether}();

        // 4 ETH = $12,000 > $10,000 → flagged
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 4 ether, "flagged expense", "capital");
        fs.approveExpense(id);

        assertTrue(fs.executeAfter(id) > 0);

        // Attempting to execute immediately reverts
        vm.expectRevert(
            abi.encodeWithSelector(FundShield.TimeLockActive.selector, id, fs.executeAfter(id), block.timestamp)
        );
        fs.executeExpense(id);
    }

    function test_TimeLock_FlaggedExpenseExecutableAfterDelay() public {
        vm.prank(ALICE);
        fs.depositFunds{value: 10 ether}();

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 4 ether, "flagged expense", "capital");
        fs.approveExpense(id);

        uint256 unlock = fs.executeAfter(id);
        vm.warp(unlock + 1);

        fs.executeExpense(id);
        assertEq(uint256(fs.getExpense(id).status), uint256(FundShield.Status.Executed));
    }

    // ─── Category spending caps ─────────────────────────────────

    function test_CategoryBudget_SetAndRead() public {
        fs.setCategoryBudget("operations", 5 ether);
        (uint256 budget, uint256 spent, uint256 remaining) = fs.getCategoryInfo("operations");
        assertEq(budget, 5 ether);
        assertEq(spent, 0);
        assertEq(remaining, 5 ether);
    }

    function test_CategoryBudget_OverBudgetIsFlagged() public {
        fs.setCategoryBudget("operations", 2 ether);

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 3 ether, "over budget", "operations");

        assertTrue(fs.getExpense(id).flagged);
    }

    function test_CategoryBudget_WithinBudgetNotFlagged() public {
        fs.setCategoryBudget("operations", 5 ether);

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 3 ether, "vendor payment", "operations");

        assertFalse(fs.getExpense(id).flagged);
    }

    function test_CategoryBudget_SpentTrackedOnExecution() public {
        fs.setCategoryBudget("operations", 10 ether);
        vm.prank(ALICE);
        fs.depositFunds{value: 5 ether}();

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 2 ether, "vendor", "operations");
        fs.approveExpense(id);
        fs.executeExpense(id);

        (, uint256 spent,) = fs.getCategoryInfo("operations");
        assertEq(spent, 2 ether);
    }

    // ─── Velocity / repeat-receiver flagging ──────────────────

    function test_Velocity_BelowThresholdNotFlagged() public {
        // Default threshold = 3; first two submissions to BOB should not flag for velocity
        vm.startPrank(ALICE);
        uint256 id1 = fs.submitExpense(BOB, 1 ether, "payment 1", "operations");
        uint256 id2 = fs.submitExpense(BOB, 1 ether, "payment 2", "operations");
        vm.stopPrank();

        assertFalse(fs.getExpense(id1).flagged);
        assertFalse(fs.getExpense(id2).flagged);
    }

    function test_Velocity_AboveThresholdIsFlagged() public {
        // 4th payment to BOB in the same window (threshold=3) → flag
        vm.startPrank(ALICE);
        fs.submitExpense(BOB, 1 ether, "payment 1", "operations");
        fs.submitExpense(BOB, 1 ether, "payment 2", "operations");
        fs.submitExpense(BOB, 1 ether, "payment 3", "operations");
        uint256 id4 = fs.submitExpense(BOB, 1 ether, "payment 4", "operations");
        vm.stopPrank();

        assertTrue(fs.getExpense(id4).flagged);
    }

    function test_Velocity_WindowResetsAfter7Days() public {
        vm.startPrank(ALICE);
        fs.submitExpense(BOB, 1 ether, "p1", "operations");
        fs.submitExpense(BOB, 1 ether, "p2", "operations");
        fs.submitExpense(BOB, 1 ether, "p3", "operations");
        vm.stopPrank();

        // Advance 7 days — window resets
        vm.warp(block.timestamp + 7 days + 1);

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "after reset", "operations");
        assertFalse(fs.getExpense(id).flagged);
    }

    function test_CategoryBudget_NoCap_NoFlag() public {
        // No budget set — should not flag for budget reason
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 100 ether, "large but no cap", "infrastructure");

        // Only flag if USD threshold exceeded; at $3k/ETH: 100 ETH = $300k > $10k → flagged for USD, not budget
        assertTrue(fs.getExpense(id).flagged);
    }

    function test_OnlyAuditorCanApproveRevert() public {
        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");

        vm.prank(BOB);
        vm.expectRevert(abi.encodeWithSelector(FundShield.OnlyAuditor.selector));
        fs.approveExpense(id);
    }

    function test_GetPendingExpenses_ReturnsPendingOnly() public {
        vm.prank(ALICE);
        fs.submitExpense(BOB, 1 ether, "pay vendor", "operations");

        vm.prank(ALICE);
        fs.submitExpense(BOB, 2 ether, "pay supplier", "operations");

        FundShield.Expense[] memory pending = fs.getPendingExpenses();
        assertEq(pending.length, 2);
    }
}
