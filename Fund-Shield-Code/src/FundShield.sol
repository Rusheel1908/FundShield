// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title FundShield
 * @notice On-chain fund transparency system.
 *         Every transaction is stored permanently and automatically
 *         flagged when it matches any suspicious-activity rule.
 * @dev Minimal, demo-focused — no access control, no upgradeability,
 *      no external dependencies. Readability > gas optimisation.
 */
contract FundShield {
    // ─────────────────────────────────────────────────────────────
    // Constants
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Transactions whose `amount` exceeds this value are flagged.
     * @dev    1 000 ETH (in wei). Chosen because legitimate operational
     *         transfers for a fund of typical hackathon / small-org size
     *         are very unlikely to exceed this in a single transaction.
     *         Adjust to your organisation's risk appetite before mainnet use.
     */
    uint256 public constant LARGE_AMOUNT_THRESHOLD = 1_000 ether;

    // ─────────────────────────────────────────────────────────────
    // Types
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Represents a single fund transfer recorded on-chain.
     * @param id        Auto-incrementing index (0-based).
     * @param sender    EOA or contract that called addTransaction().
     * @param receiver  Intended destination of the funds.
     * @param amount    Value in wei.
     * @param purpose   Human-readable description of the transfer.
     * @param flagged   True when any suspicious-activity rule fires.
     * @param timestamp Block timestamp at record time (seconds since epoch).
     */
    struct Transaction {
        uint256 id;
        address sender;
        address receiver;
        uint256 amount;
        string  purpose;
        bool    flagged;
        uint256 timestamp;
    }

    // ─────────────────────────────────────────────────────────────
    // State
    // ─────────────────────────────────────────────────────────────

    /// @notice Full history; index == transaction id.
    Transaction[] private _transactions;

    // ─────────────────────────────────────────────────────────────
    // Events
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Emitted every time a transaction is recorded.
     * @param id       The new transaction's id.
     * @param sender   Who submitted the record.
     * @param receiver Intended fund destination.
     * @param amount   Value in wei.
     * @param purpose  Transfer description.
     * @param flagged  Whether the record triggered a flag.
     */
    event TransactionLogged(
        uint256 indexed id,
        address indexed sender,
        address indexed receiver,
        uint256 amount,
        string  purpose,
        bool    flagged
    );

    // ─────────────────────────────────────────────────────────────
    // Write functions
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Record a new fund transaction and apply flagging rules.
     *
     * Flagging rules (any one suffices):
     *   1. amount == 0            — zero-value transfer is meaningless / suspicious.
     *   2. purpose is empty       — undocumented transfer is a transparency red flag.
     *   3. amount > LARGE_AMOUNT_THRESHOLD — unusually large single transfer.
     *
     * @dev Zero-address receiver is intentionally ALLOWED here so the contract
     *      can record burn-style transfers or donations to the zero address.
     *      It is NOT flagged on its own; callers should use a non-empty purpose
     *      string to document the intent. This keeps the contract minimal and
     *      avoids encoding policy that differs by organisation.
     *
     * @param receiver Destination address (may be zero — see dev note above).
     * @param amount   Transfer value in wei.
     * @param purpose  Human-readable description of the transfer.
     */
    function addTransaction(
        address receiver,
        uint256 amount,
        string calldata purpose
    ) external returns (uint256 id) {
        bool flag = _shouldFlag(amount, purpose);

        id = _transactions.length;

        _transactions.push(Transaction({
            id:        id,
            sender:    msg.sender,
            receiver:  receiver,
            amount:    amount,
            purpose:   purpose,
            flagged:   flag,
            timestamp: block.timestamp
        }));

        emit TransactionLogged(id, msg.sender, receiver, amount, purpose, flag);
    }

    // ─────────────────────────────────────────────────────────────
    // Read functions
    // ─────────────────────────────────────────────────────────────

    /// @notice Returns the transaction with the given `id`.
    /// @dev Reverts with an array-index panic if `id >= totalTransactions()`.
    function getTransaction(uint256 id)
        external
        view
        returns (Transaction memory)
    {
        return _transactions[id];
    }

    /// @notice Returns every recorded transaction in insertion order.
    /// @dev    Returning a dynamic struct array is fine for a demo / dashboard
    ///         read; avoid calling this on-chain in production loops.
    function getAllTransactions()
        external
        view
        returns (Transaction[] memory)
    {
        return _transactions;
    }

    /**
     * @notice Returns only transactions where `flagged == true`.
     * @dev    Builds the result array in two passes to avoid dynamic memory
     *         resizing. Gas cost is O(n); acceptable for a demo scenario.
     */
    function getFlaggedTransactions()
        external
        view
        returns (Transaction[] memory flagged)
    {
        uint256 total = _transactions.length;

        // First pass: count flagged entries.
        uint256 count;
        for (uint256 i; i < total; ++i) {
            if (_transactions[i].flagged) ++count;
        }

        // Second pass: populate result array.
        flagged = new Transaction[](count);
        uint256 cursor;
        for (uint256 i; i < total; ++i) {
            if (_transactions[i].flagged) {
                flagged[cursor++] = _transactions[i];
            }
        }
    }

    /// @notice Returns the total number of recorded transactions.
    function totalTransactions() external view returns (uint256) {
        return _transactions.length;
    }

    // ─────────────────────────────────────────────────────────────
    // Internal helpers
    // ─────────────────────────────────────────────────────────────

    /**
     * @dev Evaluates all flagging rules and returns true if any fires.
     *      Kept separate so the logic is trivially unit-testable and readable.
     */
    function _shouldFlag(uint256 amount, string calldata purpose)
        internal
        pure
        returns (bool)
    {
        if (amount == 0)                        return true;
        if (bytes(purpose).length == 0)         return true;
        if (amount > LARGE_AMOUNT_THRESHOLD)    return true;
        return false;
    }
}
