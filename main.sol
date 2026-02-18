// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title TrumpGold
 * @notice Reserve-backed aurum token. Chain id 0x7a09.
 * @dev Deploy nonce and salt are not part of this interface.
 *      All supply is initially minted to reserveHolder; reserveHolder may mint up to CAP_WEI.
 *      Governor is immutable and can pause/unpause transfers and minting.
 *
 * ## Supply model
 * - CAP_WEI is the maximum total supply (888_888_888 * 10**18 wei).
 * - At construction, the full cap is minted to reserveHolder.
 * - reserveHolder may mint additional tokens only up to the cap (so in practice no further mint
 *   is possible after construction unless tokens are burned first).
 * - Any holder may burn their own tokens; supply decreases.
 *
 * ## Roles
 * - governor: Can call pause() and unpause(). Set at construction and immutable.
 * - reserveHolder: Can call mint(to, value). Set at construction and immutable.
 *
 * ## Pause
 * When paused: transfer, transferFrom, and mint revert with TG_Paused. approve, decreaseAllowance,
 * increaseAllowance, and burn remain callable.
 *
 * ## Batch operations
 * batchTransfer(recipients, values) sends from msg.sender to each recipient the corresponding value.
 * batchBalanceOf(accounts) returns an array of balances. Both enforce BATCH_SIZE_LIMIT (100).
 *
 * ## ERC20 compatibility
 * Implements name(), symbol(), decimals(), totalSupply(), balanceOf(), allowance(), transfer(),
 * approve(), transferFrom(). increaseAllowance and decreaseAllowance are also provided.
 *
 * ## Security
 * - No external calls to user-supplied addresses (no call/delegatecall to accounts).
 * - Reentrancy: only state updates and events; no cross-contract calls in transfer/mint/burn.
 * - Governor and reserveHolder are immutable; cannot be changed after deployment.
 * - Pause only blocks transfer/transferFrom/mint; burn and approve remain available when paused.
 */
contract TrumpGold {
    // =========================================================================
    // CONSTANTS
    // =========================================================================
    // All token metadata and limits are fixed at compile time.
    // -------------------------------------------------------------------------

    string public constant AURUM_NAME = "TrumpGold";
    string public constant AURUM_SYMBOL = "TGOLD";
    uint8 public constant AURUM_DECIMALS = 18;
    uint256 public constant CAP_WEI = 888_888_888 * 10**18;

    /// @dev Maximum number of entries in a single batch operation to avoid gas limits.
    uint256 public constant BATCH_SIZE_LIMIT = 100;

    /// @dev Placeholder for EIP-712 domain separator if needed in future; not used in current logic.
    bytes32 public constant AURUM_DOMAIN_TYPEHASH = keccak256("TrumpGold(uint256 chainId)");

    // =========================================================================
    // STORAGE
    // =========================================================================
    // Balance and allowance mappings follow ERC20 semantics.
    // _totalMinted and _totalBurned are cumulative counters for analytics.
    // _paused is set by governor and blocks transfer/transferFrom/mint when true.
    // -------------------------------------------------------------------------

    mapping(address => uint256) private _balanceOf;
    mapping(address => mapping(address => uint256)) private _allowance;
    uint256 private _totalSupply;

    /// @notice Cumulative amount ever minted (including initial supply).
    uint256 private _totalMinted;
    /// @notice Cumulative amount ever burned.
    uint256 private _totalBurned;

    address public immutable reserveHolder;
    address public immutable governor;

    /// @notice When true, transfer, transferFrom, mint are blocked; burn and approve remain allowed.
    bool private _paused;

    // =========================================================================
    // EVENTS
    // =========================================================================
    // AurumTransfer: every move of tokens (including mint and burn with address(0)).
    // AurumApproval: allowance changes.
    // AurumMint / AurumBurn: reserve mint and user burn (also emit AurumTransfer).
    // AurumPaused / AurumUnpaused: governor toggles pause.
    // AurumBatchTransfer: emitted once per batchTransfer call with recipient count.
    // -------------------------------------------------------------------------

    event AurumTransfer(address indexed from, address indexed to, uint256 value);
    event AurumApproval(address indexed owner, address indexed spender, uint256 value);
    event AurumMint(address indexed to, uint256 value);
    event AurumBurn(address indexed from, uint256 value);
    event AurumPaused(address indexed by);
    event AurumUnpaused(address indexed by);
    event AurumBatchTransfer(address indexed from, uint256 count);

    // =========================================================================
    // CUSTOM ERRORS
    // =========================================================================
    // TG_NotGovernor: caller is not the immutable governor (pause/unpause).
    // TG_NotReserveHolder: caller is not the immutable reserveHolder (mint).
    // TG_ZeroAddress: zero address used where forbidden.
    // TG_CapExceeded: mint would exceed CAP_WEI.
    // TG_InsufficientBalance / TG_InsufficientAllowance: transfer/transferFrom checks.
    // TG_Paused / TG_NotPaused: modifier checks for pause/unpause.
    // TG_Batch*: batchTransfer / batchBalanceOf / sumBalances etc. length and size checks.
    // TG_AllowanceUnderflow: decreaseAllowance would go below zero.
    // -------------------------------------------------------------------------

    error TG_NotGovernor();
    error TG_NotReserveHolder();
    error TG_ZeroAddress();
    error TG_CapExceeded();
    error TG_InsufficientBalance();
    error TG_InsufficientAllowance();
    error TG_Paused();
    error TG_NotPaused();
    error TG_BatchLengthMismatch();
    error TG_BatchTooLarge();
    error TG_BatchZeroLength();
    error TG_AllowanceUnderflow();

    // =========================================================================
    // MODIFIERS
    // =========================================================================
    // whenNotPaused: used on transfer, transferFrom, mint. Reverts with TG_Paused if _paused is true.
    // whenPaused: used on unpause. Reverts with TG_NotPaused if _paused is false.
    // -------------------------------------------------------------------------

    modifier whenNotPaused() {
