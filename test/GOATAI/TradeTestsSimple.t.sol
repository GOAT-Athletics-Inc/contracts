// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";

event FeeDistributed(address indexed from, address indexed to, uint256 amount);
event Burn(address indexed account, uint256 amount);

contract TradeTestsSimple is Test {
    GOATAI_ERC20 public goatAI;

    address public lpPair;

    address public goatAIOps;
    address public charityWallet;
    address public treasury;
    address public dao;
    address public user1;
    address public user2;

    uint256 public charityBps;
    uint256 public treasuryBps;

    address[] public recipients;
    uint256[] public splitsBps;
    uint256 public feeBps;

    address[] public newRecipients;
    uint256[] public newSplitsBps;

    function equalWithinTolerance(
        uint256 a,
        uint256 b,
        uint256 tolerance
    ) internal pure returns (bool) {
        return (a >= b - tolerance) && (a <= b + tolerance);
    }

    function setUp() public virtual {
        vm.deal(address(this), 1 ether);

        recipients = new address[](2);
        splitsBps = new uint256[](2);

        goatAIOps = makeAddr("owner");
        charityWallet = makeAddr("charityWallet");
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        charityBps = 7500;
        treasuryBps = 2000;
        feeBps = 600;

        recipients[0] = charityWallet;
        recipients[1] = treasury;

        splitsBps[0] = charityBps;
        splitsBps[1] = treasuryBps;

        goatAI = new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            recipients,
            splitsBps
        );

        lpPair = makeAddr("lpPair");
        goatAI.setLPPair(lpPair, true);

        vm.deal(user1, 1 ether);
        vm.deal(user2, 1 ether);

        address[] memory exemptAddresses = new address[](1);
        exemptAddresses[0] = address(this);

        goatAI.setExempt(exemptAddresses, true);
    }

    function test_TradeSimple_BuyFeeNotAppliedForExempt() public {
        address[] memory exemptAddresses = new address[](1);
        exemptAddresses[0] = user2;

        goatAI.setExempt(exemptAddresses, true);

        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(lpPair, buyAmount);

        // Execute the swap
        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        assert(goatAI.balanceOf(user2) == buyAmount);
        assert(goatAI.balanceOf(lpPair) == 0);

        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // No tokens should be burned
        assert(totalSupplyBeforeSwap == totalSupplyAfterSwap);
    }

    function test_TradeSimple_SellFeeNotAppliedForExempt() public {
        uint256 sellAmount = 1_000_000_000e18;
        goatAI.transfer(user2, sellAmount);

        address[] memory exemptAddresses = new address[](1);
        exemptAddresses[0] = user2;

        goatAI.setExempt(exemptAddresses, true);

        vm.prank(user2);
        goatAI.transfer(lpPair, sellAmount);

        assert(goatAI.balanceOf(user2) == 0);
        assert(goatAI.balanceOf(lpPair) == sellAmount);

        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        uint256 amountBurned = totalSupplyBeforeSwap - totalSupplyAfterSwap;
        assert(amountBurned == 0);
    }

    function test_TradeSimple_BuyFeeApplied() public {
        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(lpPair, buyAmount);

        // Execute the swap
        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        assert(goatAI.balanceOf(user2) == 940_000_000e18);
        assert(goatAI.balanceOf(lpPair) == 0);

        assert(goatAI.balanceOf(charityWallet) == 45_000_000e18);
        assert(goatAI.balanceOf(treasury) == 12_000_000e18);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // 3% tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 3_000_000e18);
    }

    function test_TradeSimple_SellFeeApplied() public {
        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(user2, buyAmount);

        // Execute the swap
        vm.prank(user2);
        goatAI.transfer(lpPair, buyAmount);

        assert(goatAI.balanceOf(lpPair) == 940_000_000e18);
        assert(goatAI.balanceOf(user2) == 0);

        assert(goatAI.balanceOf(charityWallet) == 45_000_000e18);
        assert(goatAI.balanceOf(treasury) == 12_000_000e18);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // 3% tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 3_000_000e18);
    }

    function test_TradeSimple_Buy_BurnsEverythingIfNoRecipients() public {
        newRecipients = new address[](0);
        newSplitsBps = new uint256[](0);

        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(lpPair, buyAmount);

        uint256 expectedBurn = 60_000_000e18;

        vm.expectEmit(true, true, true, true);
        emit Burn(user2, expectedBurn);

        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        assert(goatAI.balanceOf(user2) == 940_000_000e18);
        assert(goatAI.balanceOf(lpPair) == 0);

        assert(goatAI.balanceOf(charityWallet) == 0e18);
        assert(goatAI.balanceOf(treasury) == 0e18);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // all of the fee should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, expectedBurn);
    }

    function test_TradeSimple_Sell_BurnsEverythingIfNoRecipients() public {
        newRecipients = new address[](0);
        newSplitsBps = new uint256[](0);

        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(user2, buyAmount);

        uint256 expectedBurn = 60_000_000e18;

        vm.expectEmit(true, true, true, true);
        emit Burn(user2, expectedBurn);

        vm.prank(user2);
        goatAI.transfer(lpPair, buyAmount);

        assert(goatAI.balanceOf(lpPair) == 940_000_000e18);
        assert(goatAI.balanceOf(user2) == 0);

        assert(goatAI.balanceOf(charityWallet) == 0e18);
        assert(goatAI.balanceOf(treasury) == 0e18);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // all of the fee should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, expectedBurn);
    }

    function test_TradeSimple_Buy_NoFeeSet_WithRecipients() public {
        goatAI.setBuyFeeBps(0);

        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(lpPair, buyAmount);

        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        assert(goatAI.balanceOf(user2) == buyAmount);
        assert(goatAI.balanceOf(lpPair) == 0);

        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // no tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 0);
    }

    function test_TradeSimple_Buy_NoFeeSet_NoRecipients() public {
        newRecipients = new address[](0);
        newSplitsBps = new uint256[](0);

        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        goatAI.setBuyFeeBps(0);

        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(lpPair, buyAmount);

        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        assert(goatAI.balanceOf(user2) == buyAmount);
        assert(goatAI.balanceOf(lpPair) == 0);

        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // no tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 0);
    }

    function test_TradeSimple_Sell_NoFeeSet_WithRecipients() public {
        goatAI.setSellFeeBps(0);

        uint256 sellAmount = 1_000_000_000e18;
        goatAI.transfer(user2, sellAmount);

        vm.prank(user2);
        goatAI.transfer(lpPair, sellAmount);

        assert(goatAI.balanceOf(lpPair) == sellAmount);
        assert(goatAI.balanceOf(user2) == 0);

        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // no tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 0);
    }

    function test_TradeSimple_Sell_NoFeeSet_NoRecipients() public {
        newRecipients = new address[](0);
        newSplitsBps = new uint256[](0);

        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        goatAI.setSellFeeBps(0);

        uint256 sellAmount = 1_000_000_000e18;
        goatAI.transfer(user2, sellAmount);

        vm.prank(user2);
        goatAI.transfer(lpPair, sellAmount);

        assert(goatAI.balanceOf(lpPair) == sellAmount);
        assert(goatAI.balanceOf(user2) == 0);

        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // no tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 0);
    }

    function test_TradeSimple_BuyUpdatesVote() public {
        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(lpPair, buyAmount);

        vm.expectEmit(true, true, true, true);
        emit FeeDistributed(user2, charityWallet, 45_000_000e18);

        vm.expectEmit(true, true, true, true);
        emit FeeDistributed(user2, treasury, 12_000_000e18);

        vm.expectEmit(true, true, true, true);
        emit Burn(user2, 3_000_000e18);

        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        assert(goatAI.balanceOf(user2) == 940_000_000e18);
        assert(goatAI.balanceOf(lpPair) == 0);

        assert(goatAI.balanceOf(charityWallet) == 45_000_000e18);
        assert(goatAI.balanceOf(treasury) == 12_000_000e18);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // 3% tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 3_000_000e18);

        uint256 user2Votes = goatAI.getVotes(user2);
        assertEq(user2Votes, 940_000_000e18);

        // fee recipients do not have self-delegation, and in test-setup there was no transfer
        vm.prank(charityWallet);
        goatAI.delegate(charityWallet);
        uint256 charityVotes = goatAI.getVotes(charityWallet);
        assertEq(charityVotes, 45_000_000e18);

        // fee recipients do not have self-delegation, and in test-setup there was no transfer
        vm.prank(treasury);
        goatAI.delegate(treasury);
        uint256 treasuryVotes = goatAI.getVotes(treasury);
        assertEq(treasuryVotes, 12_000_000e18);
    }

    function test_TradeSimple_SellUpdatesVote() public {
        // 1 billion GOATAI
        uint256 buyAmount = 1_000_000_000e18;
        goatAI.transfer(user2, buyAmount);

        vm.expectEmit(true, true, true, true);
        emit FeeDistributed(user2, charityWallet, 45_000_000e18);

        vm.expectEmit(true, true, true, true);
        emit FeeDistributed(user2, treasury, 12_000_000e18);

        vm.expectEmit(true, true, true, true);
        emit Burn(user2, 3_000_000e18);

        // Execute the swap
        vm.prank(user2);
        goatAI.transfer(lpPair, buyAmount);

        assert(goatAI.balanceOf(lpPair) == 940_000_000e18);
        assert(goatAI.balanceOf(user2) == 0);

        assert(goatAI.balanceOf(charityWallet) == 45_000_000e18);
        assert(goatAI.balanceOf(treasury) == 12_000_000e18);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // 3% tokens should be burned
        assertEq(totalSupplyBeforeSwap - totalSupplyAfterSwap, 3_000_000e18);

        uint256 user2Votes = goatAI.getVotes(user2);
        assert(user2Votes == 0);

        // fee recipients do not have self-delegation, and in test-setup there was no transfer
        vm.prank(charityWallet);
        goatAI.delegate(charityWallet);
        uint256 charityVotes = goatAI.getVotes(charityWallet);
        assertEq(charityVotes, 45_000_000e18);

        // fee recipients do not have self-delegation, and in test-setup there was no transfer
        vm.prank(treasury);
        goatAI.delegate(treasury);
        uint256 treasuryVotes = goatAI.getVotes(treasury);
        assertEq(treasuryVotes, 12_000_000e18);
    }

    function test_TradeSimple_BuyFee_HandlesMicroTransfers() public {
        // 1e-18 GOATAI
        uint256 buyAmount = 1;
        goatAI.transfer(lpPair, buyAmount);

        // Execute the swap
        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        assertEq(goatAI.balanceOf(user2), 1);
        assertEq(goatAI.balanceOf(lpPair), 0);

        assertEq(goatAI.balanceOf(charityWallet), 0);
        assertEq(goatAI.balanceOf(treasury), 0);

        assertEq(goatAI.balanceOf(address(goatAI)), 0);
    }

    function test_TradeSimple_BuyFee_HandlesLessExactNumbers() public {
        // number that might cause rounding imprecision
        uint256 buyAmount = 3_333_333_333e18;
        goatAI.transfer(lpPair, buyAmount);

        goatAI.setBuyFeeBps(167);

        // Execute the swap
        vm.prank(lpPair);
        goatAI.transfer(user2, buyAmount);

        uint256 expectedFee = 55_666_666_661_100 * 1e12;

        uint256 expectedUserAmount = 3_277_666_666_338_900 * 1e12;

        assertEq(goatAI.balanceOf(user2), expectedUserAmount);
        assertEq(goatAI.balanceOf(lpPair), 0);

        assertEq(expectedUserAmount + expectedFee, buyAmount);

        uint256 expectedCharityBalance = 41_749_999_995_825 * 1e12;
        assertEq(goatAI.balanceOf(charityWallet), expectedCharityBalance);

        uint256 expectedTreasuryBalance = 11_133_333_332_220 * 1e12;
        assertEq(goatAI.balanceOf(treasury), expectedTreasuryBalance);

        uint256 expectedBurnAmount = 2_783_333_333_055 * 1e12;
        uint256 supplyBeforeSwap = 1_000_000_000_000e18;
        uint256 supplyAfterSwap = goatAI.totalSupply();
        assertEq(supplyBeforeSwap - supplyAfterSwap, expectedBurnAmount);

        assertEq(
            expectedFee,
            expectedCharityBalance +
                expectedTreasuryBalance +
                expectedBurnAmount
        );

        assertEq(goatAI.balanceOf(address(goatAI)), 0);
    }

    function test_TradeSimple_DelegateGasTest() public {
        goatAI.transfer(lpPair, 100_000_000_000e18);

        address newUser = makeAddr("newUser");

        // pretend buy. measure gas for this tx
        uint256 gasBefore = gasleft();
        vm.prank(lpPair);
        goatAI.transfer(newUser, 1_000_000_000e18);
        uint256 gasAfter = gasleft();
        uint256 gasUsed = gasBefore - gasAfter;
        console2.log("Gas used for buy", gasUsed);

        // pretend buy again. measure gas for this tx
        gasBefore = gasleft();
        vm.prank(lpPair);
        goatAI.transfer(newUser, 1_000_000_000e18);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console2.log("Gas used for 2nd buy", gasUsed);

        // transfer 1st time
        address newUser2 = makeAddr("newUser2");

        gasBefore = gasleft();
        vm.prank(newUser);
        goatAI.transfer(newUser2, 500_000_000e18);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console2.log("Gas used for transfer", gasUsed);

        // transfer 2nd time
        gasBefore = gasleft();
        vm.prank(newUser);
        goatAI.transfer(newUser2, 500_000_000e18);
        gasAfter = gasleft();
        gasUsed = gasBefore - gasAfter;
        console2.log("Gas used for 2nd transfer", gasUsed);
    }
}
