// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "../../contracts/GOATAI_ERC20.sol";

contract EchidnaGOATAI_ERC20 {
    GOATAI_ERC20 private token;
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000e18;
    uint256 private constant MAX_FEE_BPS = 7_50;
    uint256 private constant MAX_NUM_RECIPIENTS = 5;

    // Track the last known total supply for testing supply changes
    uint256 private lastKnownSupply;

    constructor() {
        // Initialize with test values
        address[] memory initialRecipients = new address[](1);
        initialRecipients[0] = address(this);
        uint256[] memory initialSplits = new uint256[](1);
        initialSplits[0] = 5000; // 50%

        token = new GOATAI_ERC20(
            address(this), // admin
            500, // 5% buy fee
            500, // 5% sell fee
            initialRecipients,
            initialSplits
        );

        lastKnownSupply = INITIAL_SUPPLY;
    }

    // Total supply only changes through minting and burning
    function echidna_check_supply_changes() public view returns (bool) {
        // Since the contract doesn't have public mint function and burning only happens
        // through fees, the total supply should always be less than or equal to initial supply
        return token.totalSupply() <= INITIAL_SUPPLY;
    }

    // Fee percentages never exceed MAX_FEE_BPS
    function echidna_check_fee_limits() public view returns (bool) {
        return
            token.buyFeeBps() <= MAX_FEE_BPS &&
            token.sellFeeBps() <= MAX_FEE_BPS;
    }

    // Fee recipient splits never exceed 100%
    function echidna_check_fee_splits() public view returns (bool) {
        uint256[] memory splits = token.feeRecipientSplits();
        uint256 totalSplits = 0;

        for (uint256 i = 0; i < splits.length; i++) {
            totalSplits += splits[i];
        }

        return totalSplits <= 100_00; // 100% in basis points
    }

    // Number of recipients never exceeds MAX_NUM_RECIPIENTS
    function echidna_check_max_recipients() public view returns (bool) {
        return token.feeRecipients().length <= MAX_NUM_RECIPIENTS;
    }
}
