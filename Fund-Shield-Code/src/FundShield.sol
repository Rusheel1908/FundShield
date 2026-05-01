// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FundShield
 * @notice On-chain treasury transparency with expense approval and suspicious spending flagging.
 * @dev Minimal dependency design; includes owner/auditor roles, expense workflow, and on-chain funds execution.
 */
contract FundShield {
    // ─────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────

    enum Status {
        Pending,
        Approved,
        Executed,
        Rejected,
        Cancelled
    }

    struct Expense {
        uint256 id;
        address requester;
        address receiver;
        uint256 amount;
        string purpose;
        string category;
        bool flagged;
        Status status;
        address approver;
        string rejectReason;
        uint256 createdAt;
        uint256 updatedAt;
    }

    // ─────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────

    address public owner;
    uint256 public largeAmountThreshold;
    Expense[] private _expenses;
    mapping(address => bool) public auditors;

    // ─────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────

    event FundsDeposited(address indexed sender, uint256 amount);
    event AuditorUpdated(address indexed auditor, bool authorized);
    event LargeAmountThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event ExpenseSubmitted(
        uint256 indexed id,
        address indexed requester,
        address indexed receiver,
        uint256 amount,
        string purpose,
        string category,
        bool flagged
    );
    event ExpenseApproved(uint256 indexed id, address indexed approver);
    event ExpenseRejected(uint256 indexed id, address indexed approver, string reason);
    event ExpenseExecuted(uint256 indexed id, address indexed executor, uint256 amount);
    event ExpenseCancelled(uint256 indexed id, address indexed requester);

    // ─────────────────────────────────────────────────────────────
    // Errors
    // ─────────────────────────────────────────────────────────────

    error OnlyOwner();
    error OnlyAuditor();
    error OnlyRequester();
    error InvalidExpenseId(uint256 id);
    error InvalidStatus(Status expected, Status actual);
    error InsufficientBalance(uint256 balance, uint256 required);
    error EmptyReason();
    error AlreadyFinalized(Status actual);

    // ─────────────────────────────────────────────────────────────
    // Modifiers
    // ─────────────────────────────────────────────────────────────

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    modifier onlyAuditor() {
        if (!auditors[msg.sender]) revert OnlyAuditor();
        _;
    }

    // ─────────────────────────────────────────────────────────────
    // Constructor
    // ─────────────────────────────────────────────────────────────

    constructor() {
        owner = msg.sender;
        auditors[msg.sender] = true;
        largeAmountThreshold = 1_000 ether;
    }

    // ─────────────────────────────────────────────────────────────
    // Governance
    // ─────────────────────────────────────────────────────────────

    function setAuditor(address auditor, bool authorized) external onlyOwner {
        auditors[auditor] = authorized;
        emit AuditorUpdated(auditor, authorized);
    }

    function setLargeAmountThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = largeAmountThreshold;
        largeAmountThreshold = newThreshold;
        emit LargeAmountThresholdUpdated(oldThreshold, newThreshold);
    }

    // ─────────────────────────────────────────────────────────────
    // Funds management
    // ─────────────────────────────────────────────────────────────

    function depositFunds() external payable {
        if (msg.value == 0) revert InsufficientBalance(address(this).balance, 1);
        emit FundsDeposited(msg.sender, msg.value);
    }

    // ─────────────────────────────────────────────────────────────
    // Expense workflow
    // ─────────────────────────────────────────────────────────────

    function submitExpense(address receiver, uint256 amount, string calldata purpose, string calldata category)
        external
        returns (uint256 id)
    {
        bool flag = _shouldFlag(amount, purpose);

        id = _expenses.length;
        _expenses.push(
            Expense({
                id: id,
                requester: msg.sender,
                receiver: receiver,
                amount: amount,
                purpose: purpose,
                category: category,
                flagged: flag,
                status: Status.Pending,
                approver: address(0),
                rejectReason: "",
                createdAt: block.timestamp,
                updatedAt: block.timestamp
            })
        );

        emit ExpenseSubmitted(id, msg.sender, receiver, amount, purpose, category, flag);
    }

    function approveExpense(uint256 id) external onlyAuditor {
        Expense storage expense = _expenses[_validateExpenseId(id)];
        if (expense.status != Status.Pending) revert InvalidStatus(Status.Pending, expense.status);

        expense.status = Status.Approved;
        expense.approver = msg.sender;
        expense.updatedAt = block.timestamp;

        emit ExpenseApproved(id, msg.sender);
    }

    function rejectExpense(uint256 id, string calldata reason) external onlyAuditor {
        if (bytes(reason).length == 0) revert EmptyReason();

        Expense storage expense = _expenses[_validateExpenseId(id)];
        if (expense.status != Status.Pending) revert InvalidStatus(Status.Pending, expense.status);

        expense.status = Status.Rejected;
        expense.approver = msg.sender;
        expense.rejectReason = reason;
        expense.updatedAt = block.timestamp;

        emit ExpenseRejected(id, msg.sender, reason);
    }

    function executeExpense(uint256 id) external onlyOwner {
        Expense storage expense = _expenses[_validateExpenseId(id)];
        if (expense.status != Status.Approved) revert InvalidStatus(Status.Approved, expense.status);
        if (address(this).balance < expense.amount) revert InsufficientBalance(address(this).balance, expense.amount);

        expense.status = Status.Executed;
        expense.updatedAt = block.timestamp;

        (bool success,) = payable(expense.receiver).call{value: expense.amount}("");
        if (!success) revert InsufficientBalance(address(this).balance, expense.amount);

        emit ExpenseExecuted(id, msg.sender, expense.amount);
    }

    function cancelExpense(uint256 id) external {
        Expense storage expense = _expenses[_validateExpenseId(id)];
        if (expense.requester != msg.sender) revert OnlyRequester();
        if (expense.status != Status.Pending) revert InvalidStatus(Status.Pending, expense.status);

        expense.status = Status.Cancelled;
        expense.updatedAt = block.timestamp;

        emit ExpenseCancelled(id, msg.sender);
    }

    // ─────────────────────────────────────────────────────────────
    // Read functions
    // ─────────────────────────────────────────────────────────────

    function getExpense(uint256 id) external view returns (Expense memory) {
        return _expenses[_validateExpenseId(id)];
    }

    function getExpenses(uint256 start, uint256 count) external view returns (Expense[] memory expenses) {
        uint256 total = _expenses.length;
        if (start >= total) return new Expense[](0);

        uint256 available = total - start;
        uint256 length = count < available ? count : available;
        expenses = new Expense[](length);
        for (uint256 i = 0; i < length; ++i) {
            expenses[i] = _expenses[start + i];
        }
    }

    function getFlaggedExpenses() external view returns (Expense[] memory flagged) {
        uint256 total = _expenses.length;
        uint256 count;
        for (uint256 i = 0; i < total; ++i) {
            if (_expenses[i].flagged) ++count;
        }

        flagged = new Expense[](count);
        uint256 cursor;
        for (uint256 i = 0; i < total; ++i) {
            if (_expenses[i].flagged) {
                flagged[cursor++] = _expenses[i];
            }
        }
    }

    function getPendingExpenses() external view returns (Expense[] memory pending) {
        uint256 total = _expenses.length;
        uint256 count;
        for (uint256 i = 0; i < total; ++i) {
            if (_expenses[i].status == Status.Pending) ++count;
        }

        pending = new Expense[](count);
        uint256 cursor;
        for (uint256 i = 0; i < total; ++i) {
            if (_expenses[i].status == Status.Pending) {
                pending[cursor++] = _expenses[i];
            }
        }
    }

    function totalExpenses() external view returns (uint256) {
        return _expenses.length;
    }

    // ─────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────

    function _shouldFlag(uint256 amount, string calldata purpose) internal view returns (bool) {
        if (amount == 0) return true;
        if (bytes(purpose).length == 0) return true;
        if (amount > largeAmountThreshold) return true;
        return false;
    }

    function _validateExpenseId(uint256 id) internal view returns (uint256) {
        if (id >= _expenses.length) revert InvalidExpenseId(id);
        return id;
    }
}
