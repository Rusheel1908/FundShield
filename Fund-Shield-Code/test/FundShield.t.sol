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
