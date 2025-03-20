// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import {Nonces} from "@openzeppelin/contracts/utils/Nonces.sol";
import {IGOATAI} from "./interfaces/IGOATAI.sol";

/// @notice Thrown when an invalid admin address is provided
error InvalidAdmin(address);
/// @notice Thrown when an invalid LP pair address is provided
error InvalidLPAddress(address);
/// @dev Thrown when a specified fee exceeds maximum allowed percentage
error InvalidFeeBps(uint256);
/// @dev Thrown when an invalid fee recipient address is provided
error InvalidFeeRecipient(address);
/// @dev Thrown when a fee split percentage is invalid
error InvalidFeeSplitBps(uint256);
/// @dev Thrown when an array parameter exceeds maximum allowed length
error ExceededMaxLength(uint256 maxLength, uint256 actualLength);
/// @dev Thrown when an array parameter has length less than minimum allowed length
error MinLength(uint256 minLength);
/// @dev Thrown when array lengths do not match
error MismatchingArrayLengths(uint256 length1, uint256 length2);

/// @dev Structure containing fee calculation results
/// @param netAmount The amount remaining after fees and burn have been deducted
/// @param burnAmount The amount of tokens to be burned
/// @param recipientAmounts Array of amounts to be distributed to fee recipients
/// @param contributor The address that contributed to the fees (buyer for buy, seller for sell)
struct FeeCalculation {
    uint256 netAmount;
    uint256 burnAmount;
    uint256[] recipientAmounts;
    address contributor;
}

/// @custom:security-contact dev@goatathletics.ai
contract GOATAI_ERC20 is
    IGOATAI,
    ERC20,
    ERC20Permit,
    ERC20Votes,
    AccessControl
{
    /// @notice this role can set the buy fee, sell fee and fee splits/recipients
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /// @notice Maximum number of fee recipients allowed
    uint256 private constant MAX_NUM_RECIPIENTS = 5;

    /// @notice Maximum fee percentage allowed - 7.5%
    uint256 private constant MAX_FEE_BPS = 7_50;

    /// @notice Maximum number of accounts that can be made exempt/non-exempt from fees in a single transaction
    uint256 private constant MAX_SET_EXEMPT_LENGTH = 20;

    /// @notice buy fee in basis points
    uint256 public buyFeeBps;
    /// @notice sell fee in basis points
    uint256 public sellFeeBps;
    /// @notice array of fee recipients
    address[] private _feeRecipients;
    /// @notice array of fee splits for the recipients, in basis points
    uint256[] private _feeRecipientSplits;
    /// @notice mapping of accounts exempt from fees
    mapping(address => bool) private feeExemptions;
    /// @notice mapping of LP pairs
    mapping(address => bool) private lpPairs;

    /// @notice Event emitted when LP pair status is updated
    /// @param lpPair Address of the LP pair
    /// @param isLpPair New LP pair status
    /// @param admin Address of the admin who made the change
    event SetLPPair(
        address indexed lpPair,
        bool isLpPair,
        address indexed admin
    );

    /// @notice Event emitted when an account is set exempt or non-exempt
    /// @param account Address of the account
    /// @param exempt exemption status: true = exempt, false = non-exempt
    /// @param admin Address of the admin who made the change
    event SetExempt(
        address indexed account,
        bool exempt,
        address indexed admin
    );

    /// @notice Event emitted when the buy fee is updated
    /// @param feeBps New buy fee in basis points
    /// @param admin Address of the admin who made the change
    event SetBuyFeeBps(uint256 feeBps, address indexed admin);

    /// @notice Event emitted when the sell fee is updated
    /// @param feeBps New sell fee in basis points
    /// @param admin Address of the admin who made the change
    event SetSellFeeBps(uint256 feeBps, address indexed admin);

    /// @notice Event emitted when the fee splits are updated
    /// @param recipients The addresses of the fee recipients
    /// @param splitsBps The portion of fee, in basis points, that will be allocated to each recipient
    /// @param admin Address of the admin who made the change
    event SetFeeSplits(
        address[] recipients,
        uint256[] splitsBps,
        address indexed admin
    );

    /// @notice Event emitted when fees are distributed
    /// @param from The address of the fee contributor
    /// @param to The address of the fee recipient
    /// @param amount The amount of tokens distributed
    event FeeDistributed(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    /// @notice Event emitted when tokens are burned
    /// @param account The address of the account that funded the burn
    /// @param amount The amount of tokens burned
    event Burn(address indexed account, uint256 amount);

    /// @notice Initialize the contract
    /// @param initialAdmin The address of the initial admin of this contract. This account will also initially receive all the minted tokens on contract creation, and will distribute them to vesting contracts, multi-sigs & liquidity pool, according to tokenomics
    /// @param initialBuyFeeBps The initial buy fee, in basis points.
    /// @param initialSellFeeBps The initial sell fee, in basis points.
    /// @param initialRecipients The addresses of the fee recipients
    /// @param initialFeeSplitsBps The fee splits for each recipient, in basis points
    constructor(
        address initialAdmin,
        uint256 initialBuyFeeBps,
        uint256 initialSellFeeBps,
        address[] memory initialRecipients,
        uint256[] memory initialFeeSplitsBps
    ) ERC20("GOATAI", "GOATAI") ERC20Permit("GOATAI") {
        if (initialAdmin == address(0)) revert InvalidAdmin(address(0));

        _checkFee(initialBuyFeeBps);
        _checkFee(initialSellFeeBps);
        _checkFeeSplits(initialRecipients, initialFeeSplitsBps);

        // set fee parameters in storage
        buyFeeBps = initialBuyFeeBps;
        sellFeeBps = initialSellFeeBps;
        _feeRecipients = initialRecipients;
        _feeRecipientSplits = initialFeeSplitsBps;

        // give permissions to initial admin
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(FEE_MANAGER_ROLE, initialAdmin);

        ///@notice max supply 1 trillion
        ///@dev mint all tokens to the setup account (initialAdmin)
        ///@dev tokens will be distributed by setup account to vesting contracts, multi-sigs & liquidity pool, according to tokenomics
        _mint(initialAdmin, 1_000_000_000_000e18);
    }

    /// @dev Required override for ERC20Votes compatibility
    /// @dev Returns the current timestamp as the clock value
    /// @return Current block timestamp as uint48
    function clock() public view override returns (uint48) {
        return uint48(block.timestamp);
    }

    /// @dev Required override for ERC20Votes compatibility
    /// @return String indicating that this contract uses timestamps for clock values
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=timestamp";
    }

    /// @dev Required override needed for ERC20Votes compatibility
    function nonces(
        address owner
    ) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @notice Returns the current fee recipient addresses
    /// @return The current fee recipient addresses
    function feeRecipients() public view returns (address[] memory) {
        return _feeRecipients;
    }

    /// @notice Returns the current fee recipient splits in basis points
    /// @return The portion of fee, in basis points, that will be allocated to each recipient. If the sum of all splits is less than 10,000 BPS, the remainder of the fee will be burned. See feeBurnSplit() for the current portion of fee that gets burned.
    function feeRecipientSplits() public view returns (uint256[] memory) {
        return _feeRecipientSplits;
    }

    /// @notice Returns the current portion of the fee that gets burned, in basis points
    /// @return The current portion of the fee that gets burned, in basis points

    /// @notice Gets the current burn rate in bps in relation to the total fee distributions
    /// @dev Calculated as: 100% minus sum of all recipient split percentages
    /// @dev If no recipients are set, 100% of fees are burned
    /// @dev If sum of recipient splits is 100% no fees are burned
    /// @return Percentage of fees that will be burned, in basis points
    function feeBurnSplit() public view returns (uint256) {
        uint256 totalRecipientsBps = 0;

        uint256 rLength = _feeRecipients.length;
        if (rLength == 0) return 100_00;

        for (uint256 i = 0; i < rLength; ++i) {
            totalRecipientsBps += _feeRecipientSplits[i];
        }
        return 100_00 - totalRecipientsBps;
    }

    /// @dev Validates that a fee is within acceptable limits
    /// @param feeBps The fee in basis points to validate
    /// @dev Reverts if fee exceeds MAX_FEE_BPS
    function _checkFee(uint256 feeBps) private pure {
        if (feeBps > MAX_FEE_BPS) revert InvalidFeeBps(feeBps);
    }

    /// @dev Validates fee recipient configuration
    /// @param recipients Array of fee recipient addresses
    /// @param splitsBps Array of fee splits in basis points. Portion of fee allocated to each recipient respecitvely.
    /// @dev Checks:
    /// - Recipients array is not empty and within size limits
    /// - Each recipient is a valid address
    /// - Split percentages are valid and don't exceed 100%
    /// @dev Reverts if any validation fails
    function _checkFeeSplits(
        address[] memory recipients,
        uint256[] memory splitsBps
    ) private pure {
        uint256 rLength = recipients.length;
        if (rLength > MAX_NUM_RECIPIENTS)
            revert ExceededMaxLength(MAX_NUM_RECIPIENTS, rLength);

        if (rLength != splitsBps.length)
            revert MismatchingArrayLengths(rLength, splitsBps.length);

        uint256 totalSplitBps;

        for (uint256 i = 0; i < rLength; ++i) {
            if (splitsBps[i] == 0) revert InvalidFeeSplitBps(0);
            if (recipients[i] == address(0))
                revert InvalidFeeRecipient(address(0));

            if (splitsBps[i] > 100_00) revert InvalidFeeSplitBps(splitsBps[i]);

            totalSplitBps += splitsBps[i];
        }
        if (totalSplitBps > 100_00) revert InvalidFeeSplitBps(totalSplitBps);
    }

    /// @notice Set the buy fee, in basis points. Only callable by fee manager.
    /// @param feeBps The buy fee, in basis points
    function setBuyFeeBps(uint256 feeBps) external onlyRole(FEE_MANAGER_ROLE) {
        _checkFee(feeBps);

        buyFeeBps = feeBps;

        emit SetBuyFeeBps(feeBps, msg.sender);
    }

    /// @notice Set the sell fee, in basis points. Only callable by fee manager.
    /// @param feeBps The sell fee, in basis points.
    function setSellFeeBps(uint256 feeBps) external onlyRole(FEE_MANAGER_ROLE) {
        _checkFee(feeBps);

        sellFeeBps = feeBps;

        emit SetSellFeeBps(feeBps, msg.sender);
    }

    /// @notice Set the fee splits, i.e. how much each recipient is proportion to the fee collected. The length of recipients and splitsBps must be the same. Only callable by fee manager.
    /// @param recipients The addresses of the fee recipients
    /// @param splitsBps The portion of fee, in basis points, that will be allocated to each recipient. It is allowed for the sum of splitsBps to be less than 10,000 BPS, in which case the remainder will be burned.
    function setFeeSplits(
        address[] calldata recipients,
        uint256[] calldata splitsBps
    ) external onlyRole(FEE_MANAGER_ROLE) {
        _checkFeeSplits(recipients, splitsBps);

        _feeRecipients = recipients;
        _feeRecipientSplits = splitsBps;

        emit SetFeeSplits(recipients, splitsBps, msg.sender);
    }

    /// @notice Checks if an address is a registered liquidity pair
    /// @dev Used to determine if a transfer is a buy or sell
    /// @param account Address to check
    /// @return boolean: true if address is a registered LP pair, false otherwise
    function isLPPair(address account) public view returns (bool) {
        return lpPairs[account];
    }

    /// @notice Set the LP pair status. Only callable by admin
    /// @param lpPair The address of the LP pair
    /// @param _isLpPair The liquidity pair status (true = is a liquidity pair, false = is not a liquidity pair)
    function setLPPair(
        address lpPair,
        bool _isLpPair
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (lpPair == address(0)) revert InvalidLPAddress(address(0));

        lpPairs[lpPair] = _isLpPair;
        emit SetLPPair(lpPair, _isLpPair, msg.sender);
    }

    /// @notice Returns the exemption status of an account
    /// @param account The address of the account
    /// @return The exemption status of the account (true = exempt, false = non-exempt)
    function isExempt(address account) public view returns (bool) {
        return feeExemptions[account];
    }

    /// @notice Set the exemption status of multiple accounts. Only callable by admin
    /// @param accounts The addresses of the accounts to be set exempt or non-exempt
    /// @param exempt The exemption status to be set (true = exempt, false = non-exempt)
    function setExempt(
        address[] calldata accounts,
        bool exempt
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 aLength = accounts.length;
        if (aLength == 0) revert MinLength(1);
        if (aLength > MAX_SET_EXEMPT_LENGTH)
            revert ExceededMaxLength(MAX_SET_EXEMPT_LENGTH, aLength);

        for (uint256 i = 0; i < aLength; ++i) {
            feeExemptions[accounts[i]] = exempt;
            emit SetExempt(accounts[i], exempt, msg.sender);
        }
    }

    /// @notice Updates token balances including votes, fee calculations and distributions
    /// @dev overriden for ERC20Votes and ERC20
    /// @dev Overridden to implement fee-on-transfer mechanics
    /// @dev Process:
    /// 1. Early return for mint/burn/zero amount transfers
    /// 2. Calculate fees, if applicable, based on transfer type (buy/sell)
    /// 3. Distribute fees to recipients, if applicable (see _calculateFees)
    /// 4. Burn designated amount, if applicable (see _calculateFees)
    /// 5. Transfer remaining amount to recipient
    /// @param from Address tokens are transferred from
    /// @param to Address tokens are transferred to
    /// @param amount Original amount of tokens to transfer
    function _update(
        address from,
        address to,
        uint256 amount
    ) internal override(ERC20, ERC20Votes) {
        if (from == address(0) || to == address(0) || amount == 0) {
            super._update(from, to, amount);
            return;
        }

        FeeCalculation memory fee = _calculateFees(from, to, amount);

        ///@dev cache from storage to avoid multiple SLOADs
        address[] memory recipients = _feeRecipients;

        amount = fee.netAmount;

        uint256 rLength = fee.recipientAmounts.length;
        /// @dev distribute to recipients if any are returned. If there is a fee and no recipients are set, the whole fee will be burned.
        if (rLength > 0) {
            if (rLength != recipients.length)
                ///@dev this line is virtually impossible to reach, but we keep it for safety. Test coverage will not reach this
                revert MismatchingArrayLengths(rLength, recipients.length);

            for (uint256 i = 0; i < rLength; ++i) {
                address recipient = recipients[i];
                uint256 recipientAmount = fee.recipientAmounts[i];
                if (recipientAmount > 0) {
                    super._update(from, recipient, recipientAmount);

                    emit FeeDistributed(
                        fee.contributor,
                        recipient,
                        recipientAmount
                    );
                }
            }
        }
        if (fee.burnAmount > 0) {
            _burn(from, fee.burnAmount);
            emit Burn(fee.contributor, fee.burnAmount);
        }

        super._update(from, to, amount);

        /// @dev self-delegate on first buy or 1st transfer
        /// This is a governance token at its core, so we are prioritizing voting UX over gas efficiency.
        /// We want to avoid the need for users to remember to delegate to themselves before the voting checkpoint is created,
        /// This would be basically guaranteed to happen, and would lead to a frustrating experience.

        /// 1st buy or 1st transfer to a new account are substantially more gas-intensive,
        /// All subsequent transfers are a bit more gas-intensive than a regular ERC20 transfer.
        /// We think that the gas fees on Base are low enough for the gas-inefficiency to be acceptable.

        ///@dev exclude LP contract, as it does not vote
        if (isLPPair(to)) return;

        ///@dev if recipient has no delegates yet, delegate to self
        if (delegates(to) == address(0)) _delegate(to, to);
    }

    /// @notice Calculates fees for a token transfer, if applicable
    /// @dev Supports different fee for buys and sells, but recipients and splits are the same:
    /// - Buy: When receiving tokens from LP pair
    /// - Sell: When sending tokens to LP pair
    /// - Regular transfer/burn: No fees
    /// - Exempt accounts (e.g. DAO, charity): No fees
    /// @dev Fee distribution:
    /// 1. Calculate total fee amount
    /// 2. Distribute to recipients based on split percentages
    /// 3. Remaining fee amount is burned
    /// @param from Source address of the transfer
    /// @param to Destination address of the transfer
    /// @param amount Total amount being transferred
    /// @return fee FeeCalculation struct containing:
    /// - netAmount: Amount after deducting fees and burn
    /// - burnAmount: Amount to be burned
    /// - recipientAmounts: Array of fee amounts for each recipient
    /// - contributor: Address responsible for the fees (buyer/seller). Not needed if no fee/burn is applied
    function _calculateFees(
        address from,
        address to,
        uint256 amount
    ) private view returns (FeeCalculation memory fee) {
        ///@dev receiving tokens from LP pair = buy
        if (isLPPair(from)) {
            if (isExempt(to) || buyFeeBps == 0) {
                fee.netAmount = amount;
                return fee; // contributor and other params not needed here
            }
            fee.contributor = to;

            uint256 feeAmount = (amount * buyFeeBps) / 100_00;
            uint256 rLength = _feeRecipients.length;

            // burn all of the fee if no recipients are set
            if (rLength == 0) {
                fee.netAmount = amount - feeAmount;
                fee.burnAmount = feeAmount;
                return fee; // recipient params not needed here
            }

            uint256 recipientFeeTotal;
            uint256[] memory recipientAmounts = new uint256[](rLength);

            for (uint256 i = 0; i < rLength; ++i) {
                recipientAmounts[i] =
                    (feeAmount * _feeRecipientSplits[i]) /
                    100_00;
                recipientFeeTotal += recipientAmounts[i];
            }
            fee.netAmount = amount - feeAmount;
            fee.burnAmount = feeAmount - recipientFeeTotal;
            fee.recipientAmounts = recipientAmounts;
            return fee;
        }
        ///@dev sending tokens to LP pair = sell
        else if (isLPPair(to)) {
            if (isExempt(from) || sellFeeBps == 0) {
                fee.netAmount = amount;
                return fee; // contributor and other params not needed here
            }
            fee.contributor = from;

            uint256 feeAmount = (amount * sellFeeBps) / 100_00;
            uint256 rLength = _feeRecipients.length;

            // burn all of the fee if no recipients are set
            if (rLength == 0) {
                fee.netAmount = amount - feeAmount;
                fee.burnAmount = feeAmount;
                return fee; // recipient params not needed here
            }

            uint256 totalForRecipients;
            uint256[] memory recipientAmounts = new uint256[](rLength);

            for (uint256 i = 0; i < rLength; ++i) {
                recipientAmounts[i] =
                    (feeAmount * _feeRecipientSplits[i]) /
                    100_00;
                totalForRecipients += recipientAmounts[i];
            }
            fee.netAmount = amount - feeAmount;
            fee.burnAmount = feeAmount - totalForRecipients;
            fee.recipientAmounts = recipientAmounts;
            return fee;
        }
        // at this point, this is a regular transfer or burn
        fee.netAmount = amount;
    }

    function renounceRole(
        bytes32 role,
        address account
    ) public virtual override {
        require(
            role != DEFAULT_ADMIN_ROLE,
            "AccessControl: cannot renounce Admin role"
        );
        super.renounceRole(role, account);
    }
}
