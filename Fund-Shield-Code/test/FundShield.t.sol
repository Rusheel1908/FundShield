// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {FundShield} from "../src/FundShield.sol";

contract FundShieldTest is Test {
    FundShield public fs;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);

    function setUp() public {
        fs = new FundShield();
        vm.deal(ALICE, 10 ether);
        vm.deal(BOB, 10 ether);
    }

    function test_OwnerIsDeployerAndAuditor() public view {
        assertEq(fs.owner(), address(this));
        assertTrue(fs.auditors(address(this)));
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
        assertFalse(expense.flagged);
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

    function test_SubmitExpense_AboveThresholdIsFlagged() public {
        uint256 threshold = fs.largeAmountThreshold();

        vm.prank(ALICE);
        uint256 id = fs.submitExpense(BOB, threshold + 1, "big spend", "capital");

        assertTrue(fs.getExpense(id).flagged);
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
