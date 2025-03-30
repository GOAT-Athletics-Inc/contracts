// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {GOATAITreasury} from "../../contracts/GOATAITreasury.sol";
import {GOATAITreasurySetupTest} from "./GOATAITreasurySetup.t.sol";

event Paused(address account);
event Unpaused(address account);

error AccessControlUnauthorizedAccount(address account, bytes32 role);
error EnforcedPause();

contract GOATAITreasuryPausedTest is Test, GOATAITreasurySetupTest {
    function setUp() public override {
        super.setUp();

        vm.prank(charityWallet);
        goataiTreasury.pause();
    }

    function test_GOATAITreasury_Paused_ShouldNotWithdrawWithSwap_AsExecutor()
        public
    {
        assert(goataiTreasury.paused());

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        goataiTreasury.withdrawWithSwap(1_000_000_000e18, 500);
    }

    function test_GOATAITreasury_Paused_ShouldNotWithdrawWithSwap_AsRecipient()
        public
    {
        assert(goataiTreasury.paused());

        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        goataiTreasury.withdrawWithSwap(1_000_000_000e18, 500);
    }

    function test_GOATAITreasury_Paused_ShouldNotWithdrawDirectly_AsExecutor()
        public
    {
        assert(goataiTreasury.paused());

        vm.prank(executor);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        goataiTreasury.withdrawDirect(1_000_000_000e18);
    }

    function test_GOATAITreasury_Paused_ShouldNotWithdrawDirectly_AsRecipient()
        public
    {
        assert(goataiTreasury.paused());

        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        goataiTreasury.withdrawDirect(1_000_000_000e18);
    }

    function test_GOATAITreasury_Paused_ShouldNotWithdrawOtherToken_AsRecipient()
        public
    {
        assert(goataiTreasury.paused());

        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        goataiTreasury.withdrawOtherToken(address(USDC), 1_000_000_000e18);
    }

    function test_GOATAITreasury_Paused_ShouldPauseUnpauseAsAdmin() public {
        assert(goataiTreasury.paused());

        vm.expectEmit(true, true, true, true);
        emit Unpaused(charityWallet);

        vm.prank(charityWallet);
        goataiTreasury.unpause();
        assert(!goataiTreasury.paused());

        vm.expectEmit(true, true, true, true);
        emit Paused(charityWallet);
        vm.prank(charityWallet);
        goataiTreasury.pause();
        assert(goataiTreasury.paused());
    }

    function test_GOATAITreasury_Paused_ShouldNotUnpauseAsExecutor() public {
        assert(goataiTreasury.paused());

        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                executor,
                0x0
            )
        );
        goataiTreasury.unpause();
    }

    function test_GOATAITreasury_Paused_ShouldNotGrantRoles() public {
        assert(goataiTreasury.paused());

        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        goataiTreasury.grantRole(bytes32(0x0), randomUser);
    }

    function test_GOATAITreasury_Paused_ShouldNotSetUniswapRouter() public {
        assert(goataiTreasury.paused());

        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(EnforcedPause.selector));
        goataiTreasury.setUniswapV2Router(randomUser);
    }
}
