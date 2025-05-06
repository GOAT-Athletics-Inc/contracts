// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Router02} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IGOATAITreasury} from "./interfaces/IGOATAITreasury.sol";

/// @notice Thrown when the admin tries to renounce role
error AdminCannotRenounceRole();
/// @notice Thrown when trying to withdraw more tokens than are available
error InsufficientBalance();
/// @notice Thrown when an invalid address is provided
error InvalidAddress();
/// @notice Thrown when slippage tolerance exceeds the allowed maximum
error InvalidSlippageTolerance();
/// @notice Thrown when swap parameters are invalid
error InvalidSwapParams();
/// @notice Thrown when an invalid token address is provided
error InvalidTokenAddress();
/// @notice Thrown when attempting to withdraw zero tokens
error InvalidWithdrawalAmount();
/// @notice Thrown when the path length doesn't match the expected length
error PathMismatch();
/// @notice Thrown when a swap operation fails
error SwapError();
/// @notice Thrown when a zero address is provided where not allowed
error ZeroAddress();

/// @notice Emitted when the recipient address changes
/// @param recipient The new recipient address
event SetRecipient(address indexed recipient);
/// @notice Emitted when the base token changes
/// @param baseToken The new base token address
event SetBaseToken(address indexed baseToken);
/// @notice Emitted when the output token changes
/// @param outputToken The new output token address
event SetOutputToken(address indexed outputToken);
/// @notice Emitted when the Uniswap V2 Router address changes
/// @param uniswapV2Router The new Uniswap V2 Router address
event SetUniswapV2Router(address indexed uniswapV2Router);
/// @notice Emitted when a swap operation fails
event SwapFailed(uint256 amount, uint256 slippageToleranceBps);

/// @notice Emitted when tokens are swapped and withdrawn
/// @param baseToken The token that was swapped
/// @param amountBaseToken The amount of the base token that was swapped
/// @param baseOutputToken The token that was received
/// @param amountOutputToken The amount of the output token that was received
/// @param recipient The address that received the output tokens
event WithdrawalWithSwap(
    address indexed baseToken,
    uint256 amountBaseToken,
    address indexed baseOutputToken,
    uint256 amountOutputToken,
    address indexed recipient
);

/// @notice Emitted when tokens are withdrawn directly without swapping
/// @param token The token that was withdrawn
/// @param amount The amount of tokens that were withdrawn
/// @param recipient The address that received the tokens
event Withdrawal(
    address indexed token,
    uint256 amount,
    address indexed recipient
);

/// @title Swap Parameters Structure
/// @notice Contains parameters needed for token swaps
/// @dev Used to avoid "stack too deep" errors in the withdrawWithSwap function
struct SwapParams {
    /// @notice The base token address to swap from
    address baseToken;
    /// @notice The output token address to swap to
    address outputToken;
    /// @notice The recipient of the swapped tokens
    address recipient;
    /// @notice The amount of base tokens to swap
    uint256 amount;
    /// @notice The slippage tolerance in basis points
    uint256 slippageTolerance;
    /// @notice The minimum amount of output tokens to receive
    uint256 amountOutMin;
    /// @notice The swap path through the DEX
    address[] path;
}

/// @custom:security-contact dev@goatathletics.ai
contract GOATAITreasury is
    IGOATAITreasury,
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;

    /// @dev Storage slot for the contract's storage struct
    bytes32 private constant STORAGE_SLOT = keccak256("goataitreasury.storage");
    uint256 private constant MAX_SLIPPAGE_TOLERANCE = 10_00; // 10%

    /// @notice Main storage structure for the contract
    /// @dev Uses diamond storage pattern to allow for upgradeability
    struct Storage {
        /// @notice The address that receives the withdrawn tokens
        address recipient;
        /// @notice The token accepted for withdrawals
        address baseToken;
        /// @notice The token that will be received after swapping
        address outputToken;
        /// @notice The Uniswap V2 Router address used for swaps
        address uniswapV2Router;
    }

    /// @notice Gets the storage struct from its dedicated storage slot
    /// @return ds The storage struct
    function getStorage() internal pure returns (Storage storage ds) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            ds.slot := slot
        }
    }

    /// @notice Role identifier for executor accounts
    /// @dev Executors can execute withdrawal functions and pay gas on behalf of the recipient
    /// @dev This role is granted to the recipient and the admin by default
    bytes32 internal constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    /// @notice Disables initializers for the implementation contract
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the GOATAITreasury contract
    /// @dev Called once when the proxy is deployed
    /// @param initialRecipient The address of the initial recipient of the treasury
    /// @param initialBaseToken The address of the initial base token
    /// @param initialOutputToken The address of the initial output token
    /// @param initialUniswapV2Router The address of the initial Uniswap V2 Router
    /// @param initialExecutor The address of the initial executor that can execute the withdrawal function & pay the gas on behalf of the recipient
    function initialize(
        address initialRecipient,
        address initialBaseToken,
        address initialOutputToken,
        address initialUniswapV2Router,
        address initialExecutor
    ) public initializer {
        __AccessControl_init();
        __Pausable_init();

        if (initialRecipient == address(0)) revert ZeroAddress();
        if (initialBaseToken == address(0)) revert InvalidTokenAddress();
        if (initialOutputToken == address(0)) revert InvalidTokenAddress();
        if (initialExecutor == address(0)) revert ZeroAddress();

        ///@dev check initialBaseToken & initialOutputToken are ERC20
        if (!_isERC20(initialBaseToken)) revert InvalidTokenAddress();
        if (!_isERC20(initialOutputToken)) revert InvalidTokenAddress();

        _grantRole(DEFAULT_ADMIN_ROLE, initialRecipient);

        _grantRole(EXECUTOR_ROLE, initialRecipient);
        _grantRole(EXECUTOR_ROLE, initialExecutor);

        Storage storage s = getStorage();

        s.recipient = initialRecipient;
        s.baseToken = initialBaseToken;
        s.outputToken = initialOutputToken;
        s.uniswapV2Router = initialUniswapV2Router;
    }

    /// @notice Gets the current recipient address
    /// @return The address of the current recipient of the treasury
    function recipient() public view returns (address) {
        return getStorage().recipient;
    }

    /// @notice Sets the recipient of the treasury
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newRecipient The address of the new recipient
    function setRecipient(
        address newRecipient
    ) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRecipient == address(0)) revert ZeroAddress();
        if (newRecipient == address(this)) revert InvalidAddress();

        Storage storage s = getStorage();

        address oldRecipient = s.recipient;
        if (oldRecipient == newRecipient) revert InvalidAddress();

        s.recipient = newRecipient;
        grantRole(EXECUTOR_ROLE, newRecipient);
        grantRole(DEFAULT_ADMIN_ROLE, newRecipient);

        // keeping roles for the old recipient

        emit SetRecipient(newRecipient);
    }

    /// @notice Gets the current base token address
    /// @return The address of the base token of the treasury
    function baseToken() public view returns (address) {
        return getStorage().baseToken;
    }

    /// @notice Sets the base token of the treasury
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newBaseToken The address of the new base token
    function setBaseToken(
        address newBaseToken
    ) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newBaseToken == address(0)) revert InvalidTokenAddress();
        if (!_isERC20(newBaseToken)) revert InvalidTokenAddress();

        Storage storage s = getStorage();
        s.baseToken = newBaseToken;
        emit SetBaseToken(newBaseToken);
    }

    /// @notice Gets the current output token address
    /// @return The address of the output token for withdrawals
    function outputToken() public view returns (address) {
        return getStorage().outputToken;
    }

    /// @notice Sets the output token for withdrawals with swap
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newOutputToken The address of the new output token
    function setOutputToken(
        address newOutputToken
    ) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newOutputToken == address(0)) revert InvalidTokenAddress();
        if (!_isERC20(newOutputToken)) revert InvalidTokenAddress();

        Storage storage s = getStorage();
        s.outputToken = newOutputToken;

        emit SetOutputToken(newOutputToken);
    }

    /// @notice Gets the current Uniswap V2 Router address
    /// @return The address of the Uniswap V2 Router for swapping
    function uniswapV2Router() public view returns (address) {
        return getStorage().uniswapV2Router;
    }

    /// @notice Sets the Uniswap V2 Router for the treasury
    /// @dev Can only be called by an admin when contract is not paused
    /// @param newUniswapV2Router The address of the new Uniswap V2 Router
    function setUniswapV2Router(
        address newUniswapV2Router
    ) external whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newUniswapV2Router == address(0)) revert ZeroAddress();
        if (newUniswapV2Router == address(this)) revert InvalidAddress();

        Storage storage s = getStorage();
        s.uniswapV2Router = newUniswapV2Router;

        emit SetUniswapV2Router(newUniswapV2Router);
    }

    /// @notice Prepares swap parameters to avoid stack too deep errors
    /// @dev Creates a SwapParams struct with all necessary information for the swap
    /// @param amount The amount of base tokens to swap
    /// @param slippageToleranceBps The slippage tolerance in basis points
    /// @param router The Uniswap V2 Router interface
    /// @return swapParams The prepared swap parameters
    function _getSwapParams(
        uint256 amount,
        uint256 slippageToleranceBps,
        IUniswapV2Router02 router
    ) private view returns (SwapParams memory swapParams) {
        /// @dev validation on input params already performed in withdrawWithSwap function

        swapParams.baseToken = baseToken();
        swapParams.outputToken = outputToken();
        swapParams.recipient = recipient();

        if (swapParams.baseToken == address(0)) revert InvalidTokenAddress();
        if (swapParams.outputToken == address(0)) revert InvalidTokenAddress();
        if (swapParams.recipient == address(0)) revert ZeroAddress();
        if (swapParams.baseToken == swapParams.outputToken)
            revert InvalidSwapParams();

        swapParams.amount = amount;
        swapParams.slippageTolerance = slippageToleranceBps;

        /// @dev if baseToken or outputToken is not WETH, path will use WETH as intermediary
        if (
            swapParams.baseToken != router.WETH() &&
            swapParams.outputToken != router.WETH()
        ) {
            ///@dev swap base-token --> WETH --> output-token
            swapParams.path = new address[](3);
            swapParams.path[0] = swapParams.baseToken;
            swapParams.path[1] = router.WETH();
            swapParams.path[2] = swapParams.outputToken;
        } else {
            /// @dev otherwise swap directly between wrapped eth and other token
            swapParams.path = new address[](2);
            swapParams.path[0] = swapParams.baseToken;
            swapParams.path[1] = swapParams.outputToken;
        }

        uint256[] memory amountsOut = router.getAmountsOut(
            amount,
            swapParams.path
        );
        if (amountsOut.length != swapParams.path.length) revert PathMismatch();

        swapParams.amountOutMin =
            (amountsOut[amountsOut.length - 1] *
                (100_00 - slippageToleranceBps)) /
            100_00;
    }

    /// @notice Swaps base tokens for output tokens and sends them to the recipient
    /// @dev Uses Uniswap V2 for swapping with fee-on-transfer token support
    /// @dev Only Executors can call this function
    /// @param amount The amount of base tokens to swap
    /// @param slippageToleranceBps The maximum acceptable slippage in basis points (1/100 of 1%)
    function withdrawWithSwap(
        uint256 amount,
        uint256 slippageToleranceBps,
        uint256 deadlineOffsetSeconds
    ) external nonReentrant whenNotPaused onlyRole(EXECUTOR_ROLE) {
        if (amount == 0) revert InvalidWithdrawalAmount();
        if (slippageToleranceBps > MAX_SLIPPAGE_TOLERANCE)
            revert InvalidSlippageTolerance();

        address routerAddress = uniswapV2Router();
        if (routerAddress == address(0)) revert ZeroAddress();

        IUniswapV2Router02 router = IUniswapV2Router02(routerAddress);

        SwapParams memory swapParams = _getSwapParams(
            amount,
            slippageToleranceBps,
            router
        );

        IERC20 baseERC20 = IERC20(swapParams.baseToken);

        address cf = address(this);

        if (baseERC20.balanceOf(cf) < amount) revert InsufficientBalance();

        // Check current allowance
        uint256 currentAllowance = baseERC20.allowance(cf, routerAddress);

        // Only approve what is necessary
        if (currentAllowance < amount) {
            // resetting allowance to 0 for tokens like USDT that require it
            if (currentAllowance > 0) {
                baseERC20.safeDecreaseAllowance(
                    routerAddress,
                    currentAllowance
                );
            }
            baseERC20.safeIncreaseAllowance(routerAddress, amount);
        }

        IERC20 outputERC20 = IERC20(swapParams.outputToken);
        uint256 prevBalance = outputERC20.balanceOf(swapParams.recipient);

        try
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amount,
                swapParams.amountOutMin,
                swapParams.path,
                swapParams.recipient,
                block.timestamp + deadlineOffsetSeconds
            )
        {
            uint256 outputOut = outputERC20.balanceOf(swapParams.recipient) -
                prevBalance;

            emit WithdrawalWithSwap(
                swapParams.baseToken,
                swapParams.amount,
                swapParams.outputToken,
                outputOut,
                swapParams.recipient
            );
        } catch {
            emit SwapFailed(amount, slippageToleranceBps);
            revert SwapError();
        }
    }

    /// @notice Withdraws base tokens directly to the recipient without swapping
    /// @dev Used as a backup in case swapping fails
    /// @dev Only Executors can call this function.
    /// @param amount The amount of base tokens to withdraw
    function withdrawDirect(
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(EXECUTOR_ROLE) {
        if (amount == 0) revert InvalidWithdrawalAmount();

        address baseERC20Address = baseToken();

        IERC20 token = IERC20(baseERC20Address);
        if (token.balanceOf(address(this)) < amount)
            revert InsufficientBalance();

        address recipientAddress = recipient();
        if (recipientAddress == address(0)) revert ZeroAddress();

        token.safeTransfer(recipientAddress, amount);

        emit Withdrawal(baseERC20Address, amount, recipientAddress);
    }

    /// @notice Withdraws any token from the treasury to the recipient's address.
    /// @param tokenAddress The address of the token to withdraw.
    /// @param amount The amount of the output token to withdraw.
    /// @dev Only Admins can call this function.
    function withdrawOtherToken(
        address tokenAddress,
        uint256 amount
    ) external nonReentrant whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount == 0) revert InvalidWithdrawalAmount();

        IERC20 token = IERC20(tokenAddress);
        if (token.balanceOf(address(this)) < amount)
            revert InsufficientBalance();

        address recipientAddress = recipient();

        if (recipientAddress == address(0)) revert ZeroAddress();

        token.safeTransfer(recipientAddress, amount);

        emit Withdrawal(tokenAddress, amount, recipientAddress);
    }

    /// @notice Checks if an address is a valid ERC20 token
    /// @dev not intended to be bullet proof. Just a basic check for admin-only functions to prevent incorrect input
    /// @dev Tests by calling totalSupply() and checking the result
    /// @param token The token address to check
    /// @return True if the address is a valid ERC20 token with non-zero supply
    function _isERC20(address token) private view returns (bool) {
        if (token == address(0)) revert InvalidTokenAddress();

        ///@dev then check it's an ERC20 token
        try IERC20(token).totalSupply() returns (uint256 supply) {
            return supply > 0;
        } catch {
            return false;
        }
    }

    /// @notice Authorizes a contract upgrade
    /// @dev Can only be called by an admin
    /// @param newImplementation The address of the new implementation
    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    /// @notice Pauses all functions with the whenNotPaused modifier
    /// @dev Can only be called by an admin
    function pause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses all functions with the whenNotPaused modifier
    /// @dev Can only be called by an admin
    function unpause() public onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Adds an executor to the contract. Cannot be executed when contract is paused.
    /// @param role The role to grant.
    /// @param account The address of the executor to add.
    /// @dev override to avoid granting roles while contract is paused
    function grantRole(
        bytes32 role,
        address account
    ) public override whenNotPaused onlyRole(DEFAULT_ADMIN_ROLE) {
        super.grantRole(role, account);
    }

    /// @notice Renounce a role. Cannot renounce the DEFAULT_ADMIN_ROLE
    /// @dev This is a security measure to prevent accidental renouncement of the admin role
    /// @param role The role to renounce
    /// @param account The address of the account to renounce the role for
    /// @dev Reverts if the role is DEFAULT_ADMIN_ROLE
    function renounceRole(
        bytes32 role,
        address account
    ) public virtual override {
        if (role == DEFAULT_ADMIN_ROLE) revert AdminCannotRenounceRole();

        super.renounceRole(role, account);
    }
}
