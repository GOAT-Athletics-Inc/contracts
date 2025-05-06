// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2, Vm} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IWETH.sol";

import {GOATAITreasury} from "../../contracts/GOATAITreasury.sol";
import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";
import {MockWrappedEth} from "../utils/MockWrappedEth.sol";
import {GOATAITreasurySetupTest} from "./GOATAITreasurySetup.t.sol";

error AccessControlUnauthorizedAccount(address account, bytes32 role);
error InsufficientBalance();
error InvalidSlippageTolerance();
error InvalidWithdrawalAmount();

event WithdrawalWithSwap(
    address indexed baseToken,
    uint256 amountBaseToken,
    address indexed baseOutputToken,
    uint256 amountOutputToken,
    address indexed recipient
);
event Withdrawal(
    address indexed token,
    uint256 amount,
    address indexed recipient
);

contract GOATAITreasuryWithdrawTest is Test, GOATAITreasurySetupTest {
    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32("");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    function setUp() public override {
        super.setUp();
    }

    function test_GOATAITreasury_WithdrawToUSDC_AsExecutor() public {
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(goatAI);

        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        // Start recording logs
        vm.recordLogs();

        // Execute the swap
        uint256 slippageTolerance = 5_50;
        vm.deal(executor, 0.01 ether);
        vm.prank(executor);
        goataiTreasury.withdrawWithSwap(withdrawAmount, slippageTolerance, 300);

        assert(USDC.balanceOf(charityWallet) > 0);
        assertEq(goatAI.balanceOf(charityWallet), 0);

        assertEq(USDC.balanceOf(executor), 0);
        assertEq(goatAI.balanceOf(executor), 0);

        console2.log(
            "USDC.balanceOf(charityWallet)",
            USDC.balanceOf(charityWallet) / 10 ** USDC.decimals()
        );

        // Get recorded logs
        Vm.Log[] memory entries = vm.getRecordedLogs();

        // Find our Swap event
        bool foundSwapEvent = false;

        bytes32 swapEventSignature = keccak256(
            "WithdrawalWithSwap(address,uint256,address,uint256,address)"
        );

        for (uint i = 0; i < entries.length; i++) {
            // Check if this log is our Swap event
            // Event signature is the first 32 bytes of WithdrawalWithSwap event

            if (entries[i].topics[0] == swapEventSignature) {
                foundSwapEvent = true;

                // Parse the event data
                address tokenIn = address(
                    uint160(uint256(entries[i].topics[1]))
                );
                address tokenOut = address(
                    uint160(uint256(entries[i].topics[2]))
                );
                address recipient = address(
                    uint160(uint256(entries[i].topics[3]))
                );

                // Data contains amountIn and amountOut packed
                (uint256 loggedAmountIn, uint256 loggedAmountOut) = abi.decode(
                    entries[i].data,
                    (uint256, uint256)
                );

                assertEq(
                    tokenIn,
                    goataiTreasury.baseToken(),
                    "Incorrect logged input token"
                );
                assertEq(
                    tokenOut,
                    goataiTreasury.outputToken(),
                    "Incorrect logged output token"
                );
                assertEq(
                    loggedAmountIn,
                    withdrawAmount,
                    "Incorrect logged input amount"
                );
                assertEq(
                    recipient,
                    charityWallet,
                    "Incorrect logged recipient address"
                );

                assertEq(
                    loggedAmountOut,
                    USDC.balanceOf(charityWallet),
                    "Incorrect logged output amount"
                );
                break;
            }
        }

        // Verify that we found the event
        assertTrue(foundSwapEvent, "Swap event not emitted");
    }

    function test_GOATAITreasury_WithdrawToUSDC_AsRecipient() public {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        // Execute the swap
        uint256 slippageTolerance = 5_50;
        vm.deal(charityWallet, 0.01 ether);
        vm.prank(charityWallet);
        goataiTreasury.withdrawWithSwap(withdrawAmount, slippageTolerance, 300);

        assert(USDC.balanceOf(charityWallet) > 0);
        assertEq(goatAI.balanceOf(charityWallet), 0);

        assertEq(USDC.balanceOf(executor), 0);
        assertEq(goatAI.balanceOf(executor), 0);

        console2.log(
            "USDC.balanceOf(charityWallet)",
            USDC.balanceOf(charityWallet) / 10 ** USDC.decimals()
        );
    }

    function test_GOATAITreasury_WithdrawWithSwap_SupportsWETHBaseToken()
        public
    {
        vm.prank(charityWallet);
        goataiTreasury.setBaseToken(address(weth));

        vm.prank(charityWallet);
        goataiTreasury.setOutputToken(address(USDC));

        // wrap some ether to WETH
        uint256 wethAmount = 100 ether;
        vm.deal(treasuryAdmin, wethAmount);
        vm.prank(treasuryAdmin);
        weth.deposit{value: wethAmount}();
        assertEq(weth.balanceOf(treasuryAdmin), wethAmount);

        // transfer WETH to treasury
        vm.prank(treasuryAdmin);
        weth.transfer(address(goataiTreasury), wethAmount);
        assertEq(weth.balanceOf(address(goataiTreasury)), wethAmount);
        assertEq(goatAI.balanceOf(address(goataiTreasury)), 0);

        // Execute the swap
        uint256 slippageTolerance = 5_50;
        vm.deal(executor, 0.01 ether);
        vm.prank(executor);
        goataiTreasury.withdrawWithSwap(wethAmount, slippageTolerance, 300);

        assertEq(goataiTreasury.recipient(), charityWallet);
        assert(USDC.balanceOf(charityWallet) > 0);
        assertEq(weth.balanceOf(charityWallet), 0);

        assertEq(USDC.balanceOf(executor), 0);
        assertEq(weth.balanceOf(executor), 0);

        console2.log(
            "USDC.balanceOf(charityWallet)",
            USDC.balanceOf(charityWallet) / 10 ** USDC.decimals()
        );
    }

    function test_GOATAITreasury_WithdrawWithSwap_SupportsWETHOutputToken()
        public
    {
        vm.prank(charityWallet);
        goataiTreasury.setBaseToken(address(goatAI));

        vm.prank(charityWallet);
        goataiTreasury.setOutputToken(address(weth));

        uint256 withdrawAmount = 1_000_000_000e18;
        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        // Execute the swap
        uint256 slippageTolerance = 5_50;
        vm.deal(executor, 0.01 ether);
        vm.prank(executor);
        goataiTreasury.withdrawWithSwap(withdrawAmount, slippageTolerance, 300);

        assertEq(goataiTreasury.recipient(), charityWallet);
        assert(weth.balanceOf(charityWallet) > 0);
        assertEq(goatAI.balanceOf(charityWallet), 0);
        assertEq(USDC.balanceOf(charityWallet), 0);

        assertEq(USDC.balanceOf(executor), 0);
        assertEq(weth.balanceOf(executor), 0);

        console2.log(
            "weth.balanceOf(charityWallet)",
            weth.balanceOf(charityWallet) / 10 ** weth.decimals()
        );
    }

    function test_GOATAITreasury_WithdrawToUSDC_ErrorsIfInsufficientBalance()
        public
    {
        uint256 depositedAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), depositedAmount);

        vm.deal(charityWallet, 0.01 ether);
        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector));
        goataiTreasury.withdrawWithSwap(depositedAmount + 1, 100, 300);
    }

    function test_GOATAITreasury_WithdrawToUSDC_ErrorsAsAnybodyElse() public {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        vm.deal(randomUser, 0.01 ether);
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                randomUser,
                0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63
            )
        );
        goataiTreasury.withdrawWithSwap(withdrawAmount, 5_50, 300);
    }

    function test_GOATAITreasury_WithdrawToUSDC_ErrorsSlippageTooHigh() public {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        vm.deal(executor, 0.01 ether);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidSlippageTolerance.selector)
        );
        goataiTreasury.withdrawWithSwap(withdrawAmount, 20_00, 300);
    }

    function test_GOATAITreasury_WithdrawToUSDC_ErrorsZeroAmount() public {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        vm.deal(executor, 0.01 ether);
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidWithdrawalAmount.selector)
        );
        goataiTreasury.withdrawWithSwap(0, 5_00, 300);
    }

    function test_GOATAITreasury_WithdrawDirect_AsExecutor() public {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        vm.prank(executor);
        vm.expectEmit(true, true, true, true);
        emit Withdrawal(address(goatAI), withdrawAmount, charityWallet);
        goataiTreasury.withdrawDirect(withdrawAmount);

        assertEq(goatAI.balanceOf(charityWallet), withdrawAmount);
        assertEq(USDC.balanceOf(charityWallet), 0);
    }

    function test_GOATAITreasury_WithdrawDirect_AsRecipient() public {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        vm.deal(charityWallet, 0.01 ether);
        vm.prank(charityWallet);
        goataiTreasury.withdrawDirect(1_000_000_000e18);

        assertEq(goatAI.balanceOf(charityWallet), 1_000_000_000e18);
        assertEq(USDC.balanceOf(charityWallet), 0);
    }

    function test_GOATAITreasury_WithdrawDirect_ErrorsAsAnybodyElse() public {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        vm.deal(randomUser, 0.01 ether);
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                0xc7be087fF5E8811dcED44BB1a098832Ea3663dE8,
                0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63
            )
        );
        goataiTreasury.withdrawDirect(1_000_000_000e18);
    }

    function test_GOATAITreasury_WithdrawDirect_InsufficientBalance() public {
        uint256 depositedAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), depositedAmount);

        vm.deal(charityWallet, 0.01 ether);
        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector));
        goataiTreasury.withdrawDirect(depositedAmount + 1);
    }

    function test_GOATAITreasury_WithdrawDirect_ErrorsZeroAmount() public {
        vm.deal(charityWallet, 0.01 ether);
        vm.prank(charityWallet);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidWithdrawalAmount.selector)
        );
        goataiTreasury.withdrawDirect(0);
    }

    function test_GOATAITreasury_WithdrawOtherToken_AsAdmin() public {
        uint256 usdcAmount = 10_000 * (10 ** USDC.decimals());

        // buy some USDC
        address[] memory path = new address[](2);
        path[0] = address(weth);
        path[1] = address(USDC);

        vm.deal(treasuryAdmin, 100 ether);
        vm.prank(treasuryAdmin);
        IUniswapV2Router02(router)
            .swapExactETHForTokensSupportingFeeOnTransferTokens{
            value: 80 ether
        }(usdcAmount, path, treasuryAdmin, block.timestamp + 1);

        assert(USDC.balanceOf(treasuryAdmin) >= usdcAmount);

        vm.prank(treasuryAdmin);
        USDC.transfer(address(goataiTreasury), usdcAmount);

        assertEq(USDC.balanceOf(charityWallet), 0);

        vm.deal(charityWallet, 0.01 ether);
        vm.prank(charityWallet);
        goataiTreasury.withdrawOtherToken(address(USDC), usdcAmount);

        assertEq(USDC.balanceOf(charityWallet), usdcAmount);
    }

    function test_GOATAITreasury_WithdrawOtherToken_ErrorsAsAnybodyElse()
        public
    {
        uint256 withdrawAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), withdrawAmount);

        vm.deal(randomUser, 0.01 ether);
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                0xc7be087fF5E8811dcED44BB1a098832Ea3663dE8,
                0x0000000000000000000000000000000000000000000000000000000000000000
            )
        );
        goataiTreasury.withdrawOtherToken(address(USDC), 1_000_000_000e18);
    }

    function test_GOATAITreasury_WithdrawOtherToken_InsufficientBalance()
        public
    {
        uint256 depositedAmount = 1_000_000_000e18;

        goatAI.transfer(address(goataiTreasury), depositedAmount);

        vm.deal(charityWallet, 0.01 ether);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalance.selector));
        vm.prank(charityWallet);
        goataiTreasury.withdrawOtherToken(address(goatAI), depositedAmount + 1);
    }

    function test_GOATAITreasury_WithdrawOtherToken_ErrorsZeroAmount() public {
        vm.deal(charityWallet, 0.01 ether);
        vm.prank(charityWallet);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidWithdrawalAmount.selector)
        );
        goataiTreasury.withdrawOtherToken(address(goatAI), 0);
    }

    function test_GOATAITreasury_Recipient_CanKickOutInitialAdmin() public {
        assert(goataiTreasury.hasRole(DEFAULT_ADMIN_ROLE, charityWallet));

        vm.prank(charityWallet);
        goataiTreasury.revokeRole(DEFAULT_ADMIN_ROLE, treasuryAdmin);

        assert(!goataiTreasury.hasRole(DEFAULT_ADMIN_ROLE, treasuryAdmin));
    }
}
