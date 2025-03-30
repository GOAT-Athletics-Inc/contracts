// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

interface IGOATAITreasury {
    /// @notice Gets the current recipient address
    /// @return The address of the current recipient of the treasury
    function recipient() external view returns (address);

    /// @notice Sets the recipient of the treasury
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newRecipient The address of the new recipient
    function setRecipient(address newRecipient) external;

    /// @notice Gets the current base token address
    /// @return The address of the base token of the treasury
    function baseToken() external view returns (address);

    /// @notice Sets the base token of the treasury
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newBaseToken The address of the new base token
    function setBaseToken(address newBaseToken) external;

    /// @notice Gets the current output token address
    /// @return The address of the output token for withdrawals
    function outputToken() external view returns (address);

    /// @notice Sets the output token for withdrawals with swap
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newOutputToken The address of the new output token
    function setOutputToken(address newOutputToken) external;

    /// @notice Gets the current Uniswap V2 Router address
    /// @return The address of the Uniswap V2 Router for swapping
    function uniswapV2Router() external view returns (address);

    /// @notice Sets the Uniswap V2 Router for the treasury
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newUniswapV2Router The address of the new Uniswap V2 Router
    function setUniswapV2Router(address newUniswapV2Router) external;

    /// @notice Swaps base tokens for output tokens and sends them to the recipient
    /// @dev Uses Uniswap V2 for swapping with fee-on-transfer token support
    /// @dev Only Executors can call this function
    /// @param amount The amount of base tokens to swap
    /// @param slippageToleranceBps The maximum acceptable slippage in basis points (1/100 of 1%)
    function withdrawWithSwap(
        uint256 amount,
        uint256 slippageToleranceBps
    ) external;

    /// @notice Withdraws base tokens directly to the recipient without swapping
    /// @dev Used as a backup in case swapping fails
    /// @dev Only Executors can call this function.
    /// @param amount The amount of base tokens to withdraw
    function withdrawDirect(uint256 amount) external;

    /// @notice Withdraws any token from the treasury to the recipient's address.
    /// @param tokenAddress The address of the token to withdraw.
    /// @param amount The amount of the output token to withdraw.
    /// @dev Only Admins can call this function.
    function withdrawOtherToken(address tokenAddress, uint256 amount) external;

    /// @notice Pauses all functions with the whenNotPaused modifier
    /// @dev Can only be called by an admin
    function pause() external;

    /// @notice Unpauses all functions with the whenNotPaused modifier
    /// @dev Can only be called by an admin
    function unpause() external;
}
