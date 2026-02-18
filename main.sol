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
