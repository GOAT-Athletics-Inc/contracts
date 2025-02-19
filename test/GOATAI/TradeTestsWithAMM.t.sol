// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";
import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";
import {MockWrappedEth} from "../utils/MockWrappedEth.sol";

contract TradeTestsWithAMMTest is Test {
    GOATAI_ERC20 public goatAI;

    address public lpPair;
    address factory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    MockWrappedEth weth;
    ERC20 USDC;

    address pair;

    uint256 forkId;

    address public goatAIOps;
    address public charityWallet;
    address public treasury;
    address public dao;
    address public otherLPPair1;
    address public otherLPPair2;
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
        forkId = vm.createFork("https://mainnet.base.org");
        vm.selectFork(forkId);

        vm.deal(address(this), 100 ether);

        weth = MockWrappedEth(0x4200000000000000000000000000000000000006);
        USDC = ERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

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

        lpPair = IUniswapV2Factory(factory).createPair(
            address(weth),
            address(goatAI)
        );

        uint256 liquidityGOATAI = 100_000_000_000e18;

        // Approve the router to spend the token
        goatAI.approve(address(router), liquidityGOATAI);

        IUniswapV2Router01(router).addLiquidityETH{value: 10 ether}(
            address(goatAI),
            liquidityGOATAI, // amountTokenDesired
            liquidityGOATAI, // amountTokenMin
            10 ether, // amountETHMin
            goatAIOps, // recipient of LP tokens
            block.timestamp + 1 // deadline
        );

        goatAI.setLPPair(lpPair, true);
    }

    function test_Trade_BuyFeeNotAppliedForExempt() public {
        address[] memory exemptAddresses = new address[](1);
        exemptAddresses[0] = user2;

        goatAI.setExempt(exemptAddresses, true);

        vm.deal(user2, 10 ether);

        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(goatAI);

        // Execute the swap
        vm.prank(user2);
        IUniswapV2Router02(router)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            100_000_000e18, // Minimum amount of GOATAI to receive (0 = accept any amount of token)
            path,
            user2, // recipient of GOATAI
            block.timestamp + 1
        );

        assert(goatAI.balanceOf(user2) > 0);
        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        // No tokens should be burned
        assert(totalSupplyBeforeSwap == totalSupplyAfterSwap);
    }

    function test_Trade_SellFeeNotAppliedForExempt() public {
        uint256 sellAmount = 1_000_000_000e18;
        goatAI.transfer(user2, sellAmount);

        address[] memory exemptAddresses = new address[](1);
        exemptAddresses[0] = user2;

        goatAI.setExempt(exemptAddresses, true);

        vm.deal(user2, 10 ether);

        address[] memory path = new address[](2);
        path[0] = address(goatAI);
        path[1] = address(weth);

        vm.prank(user2);
        goatAI.approve(router, sellAmount);

        // Execute the swap
        vm.prank(user2);
        IUniswapV2Router02(router)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
                sellAmount, // Amount of GOATAI to sell
                0, // Minimum amount of Eth to receive (0 = accept any amount of token)
                path,
                user2, // recipient of Eth
                block.timestamp + 1
            );

        assert(goatAI.balanceOf(user2) == 0);
        assert(goatAI.balanceOf(charityWallet) == 0);
        assert(goatAI.balanceOf(treasury) == 0);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;
        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        uint256 amountBurned = totalSupplyBeforeSwap - totalSupplyAfterSwap;
        assert(amountBurned == 0);
    }

    function test_Trade_BuyFeeApplied() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(goatAI);

        vm.deal(user1, 100 ether);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;

        // Execute the swap
        vm.prank(user1);
        IUniswapV2Router02(router)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            100_000_000e18, // Minimum amount of GOATAI to receive (0 = accept any amount of token)
            path,
            user1, // recipient of GOATAI
            block.timestamp + 1
        );
        uint256 user1Balance = goatAI.balanceOf(user1);
        assert(user1Balance > 0);

        uint256 charityBalance = goatAI.balanceOf(charityWallet);
        assert(charityBalance > 0);

        uint256 treasuryBalance = goatAI.balanceOf(treasury);
        assert(treasuryBalance > 0);

        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        uint256 amountBurned = totalSupplyBeforeSwap - totalSupplyAfterSwap;
        assert(amountBurned > 0);

        uint256 totalTradeBeforeFee = user1Balance +
            charityBalance +
            treasuryBalance +
            amountBurned;

        uint256 feeApplied = totalTradeBeforeFee - user1Balance;
        assertEq(feeApplied, (totalTradeBeforeFee * feeBps) / 100_00);

        // account for rounding errors
        uint256 tolerance = 5;
        assert(
            equalWithinTolerance(
                user1Balance,
                (totalTradeBeforeFee * (100_00 - feeBps)) / 100_00,
                tolerance
            )
        );

        assertEq(charityBalance, (feeApplied * charityBps) / 100_00);
        assertEq(treasuryBalance, (feeApplied * treasuryBps) / 100_00);

        // account for rounding errors
        assert(
            equalWithinTolerance(
                amountBurned,
                (feeApplied * (100_00 - (charityBps + treasuryBps))) / 100_00,
                tolerance
            )
        );
    }

    function test_Trade_SellFeeApplied() public {
        uint256 sellAmount = 1_000_000_000e18;

        goatAI.transfer(user1, sellAmount);

        vm.deal(user1, 10 ether);

        address[] memory path = new address[](2);
        path[0] = address(goatAI);
        path[1] = address(weth);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;

        vm.prank(user1);
        goatAI.approve(router, sellAmount);

        // Execute the swap
        vm.prank(user1);
        IUniswapV2Router02(router)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
                sellAmount,
                0, // Minimum amount of Eth to receive (0 = accept any amount of token)
                path,
                user1, // recipient of Eth
                block.timestamp + 1
            );

        uint256 user1Balance = goatAI.balanceOf(user1);
        assert(user1Balance == 0);

        uint256 charityBalance = goatAI.balanceOf(charityWallet);
        assert(charityBalance > 0);

        uint256 treasuryBalance = goatAI.balanceOf(treasury);
        assert(treasuryBalance > 0);

        uint256 totalSupplyAfterSwap = goatAI.totalSupply();
        uint256 amountBurned = totalSupplyBeforeSwap - totalSupplyAfterSwap;
        assert(amountBurned > 0);

        uint256 totalTradeBeforeFee = user1Balance +
            charityBalance +
            treasuryBalance +
            amountBurned;

        uint256 feeApplied = totalTradeBeforeFee - user1Balance;

        assertEq(feeApplied, (sellAmount * feeBps) / 100_00);

        assertEq(charityBalance, (feeApplied * charityBps) / 100_00);
        assertEq(treasuryBalance, (feeApplied * treasuryBps) / 100_00);
        assert(
            amountBurned >=
                (feeApplied * (100_00 - (charityBps + treasuryBps))) / 100_00
        );
    }

    function test_Trade_BuyUpdatesVote() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(goatAI);

        vm.deal(user1, 100 ether);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;

        // Execute the swap
        vm.prank(user1);
        IUniswapV2Router02(router)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            100_000_000e18, // Minimum amount of GOATAI to receive (0 = accept any amount of token)
            path,
            user1, // recipient of GOATAI
            block.timestamp + 1
        );

        vm.prank(user1);
        goatAI.delegate(user1);
        uint256 user1Votes = goatAI.getVotes(user1);
        assert(user1Votes > 0);

        vm.prank(charityWallet);
        goatAI.delegate(charityWallet);
        uint256 charityVotes = goatAI.getVotes(charityWallet);
        assert(charityVotes > 0);

        vm.prank(treasury);
        goatAI.delegate(treasury);
        uint256 treasuryVotes = goatAI.getVotes(treasury);
        assert(treasuryVotes > 0);

        uint256 totalSupplyAfterSwap = goatAI.totalSupply();

        uint256 amountBurned = totalSupplyBeforeSwap - totalSupplyAfterSwap;
        assert(amountBurned > 0);

        uint256 totalTradeBeforeFee = user1Votes +
            charityVotes +
            treasuryVotes +
            amountBurned;

        uint256 feeApplied = totalTradeBeforeFee - user1Votes;
        assertEq(feeApplied, (totalTradeBeforeFee * feeBps) / 100_00);

        // account for rounding errors
        uint256 tolerance = 5;
        assert(
            equalWithinTolerance(
                user1Votes,
                (totalTradeBeforeFee * (100_00 - feeBps)) / 100_00,
                tolerance
            )
        );

        assertEq(charityVotes, (feeApplied * charityBps) / 100_00);
        assertEq(treasuryVotes, (feeApplied * treasuryBps) / 100_00);

        // account for rounding errors
        assert(
            equalWithinTolerance(
                amountBurned,
                (feeApplied * (100_00 - (charityBps + treasuryBps))) / 100_00,
                tolerance
            )
        );
    }

    function test_Trade_SellUpdatesVote() public {
        uint256 sellAmount = 1_000_000_000e18;

        goatAI.transfer(user1, sellAmount);

        vm.deal(user1, 10 ether);

        address[] memory path = new address[](2);
        path[0] = address(goatAI);
        path[1] = address(weth);

        uint256 totalSupplyBeforeSwap = 1_000_000_000_000e18;

        vm.prank(user1);
        goatAI.approve(router, sellAmount);

        // Execute the swap
        vm.prank(user1);
        IUniswapV2Router02(router)
            .swapExactTokensForETHSupportingFeeOnTransferTokens(
                sellAmount,
                0, // Minimum amount of Eth to receive (0 = accept any amount of token)
                path,
                user1, // recipient of Eth
                block.timestamp + 1
            );

        vm.prank(user1);
        goatAI.delegate(user1);
        uint256 user1Votes = goatAI.getVotes(user1);
        assert(user1Votes == 0);

        vm.prank(charityWallet);
        goatAI.delegate(charityWallet);
        uint256 charityVotes = goatAI.getVotes(charityWallet);
        assert(charityVotes > 0);

        vm.prank(treasury);
        goatAI.delegate(treasury);
        uint256 treasuryVotes = goatAI.getVotes(treasury);
        assert(treasuryVotes > 0);

        uint256 totalSupplyAfterSwap = goatAI.totalSupply();
        uint256 amountBurned = totalSupplyBeforeSwap - totalSupplyAfterSwap;
        assert(amountBurned > 0);

        uint256 totalTradeBeforeFee = user1Votes +
            charityVotes +
            treasuryVotes +
            amountBurned;

        uint256 feeApplied = totalTradeBeforeFee - user1Votes;

        assertEq(feeApplied, (sellAmount * feeBps) / 100_00);

        assertEq(charityVotes, (feeApplied * charityBps) / 100_00);
        assertEq(treasuryVotes, (feeApplied * treasuryBps) / 100_00);
        assert(
            amountBurned >=
                (feeApplied * (100_00 - (charityBps + treasuryBps))) / 100_00
        );
    }

    function test_Trade_CharitySellGOATAIForUSDC() public {
        uint256 sellAmount = 1_000_000_000e18;

        goatAI.transfer(charityWallet, sellAmount);
        vm.deal(charityWallet, 1 ether);

        address[] memory exemptAddresses = new address[](1);
        exemptAddresses[0] = charityWallet;

        goatAI.setExempt(exemptAddresses, true);

        address[] memory path = new address[](3);
        path[0] = address(goatAI);
        path[1] = address(weth);
        path[2] = address(USDC);

        vm.prank(charityWallet);
        goatAI.approve(router, sellAmount);

        // Execute the swap
        vm.prank(charityWallet);
        IUniswapV2Router02(router)
            .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                sellAmount,
                100, // Minimum amount of USDC to receive (0 = accept any amount of token)
                path,
                charityWallet, // recipient of USDC
                block.timestamp + 1
            );

        assert(goatAI.balanceOf(charityWallet) == 0);

        console2.log(
            "USDC balance of charityWallet",
            USDC.balanceOf(charityWallet)
        );
        assert(USDC.balanceOf(charityWallet) > 0);
    }
}
