// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);

    function decimals() external view returns (uint8);
}

/**
 * @title FundShield
 * @notice On-chain treasury transparency with expense approval, multi-sig auditor sign-off,
 *         and USD-denominated suspicious spending flagging via Chainlink price feed.
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
        address approver;       // last auditor whose signature completed the quorum
        string rejectReason;
        uint256 createdAt;
        uint256 updatedAt;
        uint256 approvalCount;  // number of auditor signatures collected so far
    }

    // ─────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────

    address public owner;
    AggregatorV3Interface public priceFeed;
    uint256 public largeAmountThresholdUSD; // 8-decimal USD, e.g. 10_000e8 = $10,000
    uint256 public requiredApprovals;       // quorum: N auditors must sign before Approved
    Expense[] private _expenses;
    mapping(address => bool) public auditors;
    // expenseId → auditorAddress → has signed
    mapping(uint256 => mapping(address => bool)) private _approvedBy;
    // category → spending cap in wei (0 = no cap)
    mapping(string => uint256) public categoryBudget;
    // category → total wei of non-rejected/cancelled expenses
    mapping(string => uint256) public categorySpent;

    // ─────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────

    event FundsDeposited(address indexed sender, uint256 amount);
    event AuditorUpdated(address indexed auditor, bool authorized);
    event LargeAmountThresholdUpdated(uint256 oldThreshold, uint256 newThreshold);
    event RequiredApprovalsUpdated(uint256 oldRequired, uint256 newRequired);
    event CategoryBudgetSet(string category, uint256 budget);
    event CategorySpentUpdated(string category, uint256 spent, uint256 budget);
    event ExpenseSubmitted(
        uint256 indexed id,
        address indexed requester,
        address indexed receiver,
        uint256 amount,
        string purpose,
        string category,
        bool flagged
    );
    event ExpenseSigned(uint256 indexed id, address indexed auditor, uint256 approvalCount, uint256 required);
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
    error AlreadySigned(uint256 id, address auditor);
    error InvalidQuorum(uint256 required);
    error CategoryBudgetExceeded(string category, uint256 budget, uint256 spent, uint256 requested);

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

    constructor(address _priceFeed) {
        owner = msg.sender;
        auditors[msg.sender] = true;
        priceFeed = AggregatorV3Interface(_priceFeed);
        largeAmountThresholdUSD = 10_000e8; // default $10,000
        requiredApprovals = 1;              // default: single auditor (backwards-compatible)
    }

    // ─────────────────────────────────────────────────────────────
    // Governance
    // ─────────────────────────────────────────────────────────────

    function setAuditor(address auditor, bool authorized) external onlyOwner {
        auditors[auditor] = authorized;
        emit AuditorUpdated(auditor, authorized);
    }

    function setLargeAmountThresholdUSD(uint256 newThresholdUSD) external onlyOwner {
        uint256 oldThreshold = largeAmountThresholdUSD;
        largeAmountThresholdUSD = newThresholdUSD;
        emit LargeAmountThresholdUpdated(oldThreshold, newThresholdUSD);
    }

    /// @notice Set a per-category spending cap (in wei). Pass 0 to remove the cap.
    function setCategoryBudget(string calldata category, uint256 budget) external onlyOwner {
        categoryBudget[category] = budget;
        emit CategoryBudgetSet(category, budget);
    }

    /// @notice Set how many distinct auditor signatures are required to approve an expense.
    function setRequiredApprovals(uint256 newRequired) external onlyOwner {
        if (newRequired == 0) revert InvalidQuorum(newRequired);
        uint256 old = requiredApprovals;
        requiredApprovals = newRequired;
        emit RequiredApprovalsUpdated(old, newRequired);
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
        bool flag = _shouldFlag(amount, purpose, category);

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
                updatedAt: block.timestamp,
                approvalCount: 0
            })
        );

        emit ExpenseSubmitted(id, msg.sender, receiver, amount, purpose, category, flag);
    }

    /// @notice Auditor signs an expense. Once `requiredApprovals` distinct signatures are
    ///         collected the expense transitions to Approved automatically.
    function approveExpense(uint256 id) external onlyAuditor {
        Expense storage expense = _expenses[_validateExpenseId(id)];
        if (expense.status != Status.Pending) revert InvalidStatus(Status.Pending, expense.status);
        if (_approvedBy[id][msg.sender]) revert AlreadySigned(id, msg.sender);

        _approvedBy[id][msg.sender] = true;
        expense.approvalCount += 1;
        expense.updatedAt = block.timestamp;

        emit ExpenseSigned(id, msg.sender, expense.approvalCount, requiredApprovals);

        if (expense.approvalCount >= requiredApprovals) {
            expense.status = Status.Approved;
            expense.approver = msg.sender;
            emit ExpenseApproved(id, msg.sender);
        }
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

        categorySpent[expense.category] += expense.amount;
        emit CategorySpentUpdated(expense.category, categorySpent[expense.category], categoryBudget[expense.category]);

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

    /// @notice Check whether a specific auditor has already signed a given expense.
    function hasApproved(uint256 id, address auditor) external view returns (bool) {
        return _approvedBy[id][auditor];
    }

    /// @notice Returns the budget cap, amount spent, and remaining headroom for a category.
    function getCategoryInfo(string calldata category)
        external
        view
        returns (uint256 budget, uint256 spent, uint256 remaining)
    {
        budget = categoryBudget[category];
        spent = categorySpent[category];
        remaining = (budget > 0 && budget > spent) ? budget - spent : 0;
    }

    /// @notice Returns the latest ETH/USD price from Chainlink (8 decimals, e.g. 300000000000 = $3,000).
    function getLatestETHPrice() public view returns (uint256) {
        (, int256 price,,,) = priceFeed.latestRoundData();
        if (price <= 0) return 0;
        return uint256(price);
    }

    /// @notice Converts a wei amount to USD value (8 decimals). Returns 0 if price feed unavailable.
    function getAmountInUSD(uint256 weiAmount) public view returns (uint256) {
        uint256 ethPrice = getLatestETHPrice();
        if (ethPrice == 0) return 0;
        return (weiAmount * ethPrice) / 1e18;
    }

    // ─────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────

    function _shouldFlag(uint256 amount, string calldata purpose, string calldata category)
        internal
        view
        returns (bool)
    {
        if (amount == 0) return true;
        if (bytes(purpose).length == 0) return true;
        uint256 amountInUSD = getAmountInUSD(amount);
        // Skip USD check if price feed unavailable (avoids false-positives on feed outage)
        if (amountInUSD > 0 && amountInUSD > largeAmountThresholdUSD) return true;
        // Flag if submission would exceed the category spending cap
        uint256 cap = categoryBudget[category];
        if (cap > 0 && categorySpent[category] + amount > cap) return true;
        return false;
    }

    function _validateExpenseId(uint256 id) internal view returns (uint256) {
        if (id >= _expenses.length) revert InvalidExpenseId(id);
        return id;
    }
}
