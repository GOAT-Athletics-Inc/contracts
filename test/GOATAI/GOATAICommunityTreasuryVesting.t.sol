// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {VestingWallet} from "@openzeppelin/contracts/finance/VestingWallet.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";
import {TestGOATAIGovernor} from "../utils/TestGOATAIGovernor.sol";

event ERC20Released(address indexed token, uint256 amount);

contract GOATAIVotesTest is Test {
    GOATAI_ERC20 public goatAI;
    TestGOATAIGovernor public dao;
    TimelockController timelock;
    VestingWallet public daoVestingWallet;

    address public charityWallet;
    address public treasury;
    address public goatAIOps;
    address public user1;

    uint256 public charityBps;
    uint256 public treasuryBps;

    address[] public recipients;
    uint256[] public splitsBps;
    uint256 public feeBps;

    uint64 public startTimestamp;
    uint64 public durationSeconds;

    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0x0);
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    function setUp() public {
        charityWallet = makeAddr("charityWallet");
        treasury = makeAddr("treasury");
        goatAIOps = makeAddr("goatAIOps");
        user1 = makeAddr("user1");

        recipients = new address[](2);
        splitsBps = new uint256[](2);

        recipients[0] = charityWallet;
        recipients[1] = treasury;

        charityBps = 7000;
        treasuryBps = 2500;
        feeBps = 600;

        splitsBps[0] = charityBps;
        splitsBps[1] = treasuryBps;

        goatAI = new GOATAI_ERC20(
            goatAIOps,
            feeBps,
            feeBps,
            recipients,
            splitsBps
        );

        vm.prank(goatAIOps);
        goatAI.delegate(goatAIOps);

        vm.prank(goatAIOps);
        goatAI.transfer(charityWallet, 10_000_000_000e18);
        vm.prank(charityWallet);
        goatAI.delegate(charityWallet);

        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);

        // centralize management at the beginning
        proposers[0] = goatAIOps;
        executors[0] = goatAIOps;

        timelock = new TimelockController(
            2 days,
            proposers,
            executors,
            goatAIOps
        );

        dao = new TestGOATAIGovernor(IVotes(goatAI), timelock);

        startTimestamp = uint64(block.timestamp) + (6 * 31 days);
        durationSeconds = 2.5 * 365 days;

        daoVestingWallet = new VestingWallet(
            address(dao), // beneficiary
            startTimestamp,
            durationSeconds
        );

        vm.prank(goatAIOps);
        goatAI.transfer(address(daoVestingWallet), 200_000_000_000e18);
    }

    function test_GOATAI_CommunityTreasury_VestingContract_InitsWithLockedFunds()
        public
    {
        assertEq(
            goatAI.balanceOf(address(daoVestingWallet)),
            200_000_000_000e18
        );
        assertEq(goatAI.balanceOf(address(dao)), 0);

        assertEq(daoVestingWallet.releasable(address(goatAI)), 0);
        assertEq(daoVestingWallet.released(address(goatAI)), 0);
        assertEq(
            daoVestingWallet.vestedAmount(
                address(goatAI),
                uint64(block.timestamp)
            ),
            0
        );

        vm.expectEmit(true, true, true, true);
        emit ERC20Released(address(goatAI), 0);
        daoVestingWallet.release(address(goatAI));

        assertEq(goatAI.balanceOf(address(dao)), 0);
    }

    function test_GOATAI_CommunityTreasury_VestingContract_UnlocksSomeAtFirstPeriod()
        public
    {
        vm.warp(startTimestamp);
        assertEq(daoVestingWallet.releasable(address(goatAI)), 0);

        vm.warp(startTimestamp + 1 days);
        assert(daoVestingWallet.releasable(address(goatAI)) > 0);

        daoVestingWallet.release(address(goatAI));
        assert(daoVestingWallet.released(address(goatAI)) > 0);
    }

    function test_GOATAI_CommunityTreasury_VestingContract_AnybodyCanReleaseFunds()
        public
    {
        vm.warp(startTimestamp + 1 days);

        assert(daoVestingWallet.releasable(address(goatAI)) > 0);

        vm.prank(user1);
        daoVestingWallet.release(address(goatAI));

        assert(goatAI.balanceOf(address(dao)) > 0);
        assertEq(goatAI.balanceOf(address(user1)), 0);
    }

    function test_GOATAI_CommunityTreasury_VestingContract_UnlocksAllAtEnd()
        public
    {
        vm.warp(startTimestamp + durationSeconds);
        assertEq(
            daoVestingWallet.releasable(address(goatAI)),
            200_000_000_000e18
        );

        vm.expectEmit(true, true, true, true);
        emit ERC20Released(address(goatAI), 200_000_000_000e18);
        daoVestingWallet.release(address(goatAI));
        assertEq(goatAI.balanceOf(address(dao)), 200_000_000_000e18);
    }

    function test_GOATAI_CommunityTreasury_VestingContract_FollowsReleaseSchedule()
        public
    {
        vm.warp(startTimestamp + durationSeconds / 2);
        assertEq(
            daoVestingWallet.releasable(address(goatAI)),
            100_000_000_000e18
        );
        daoVestingWallet.release(address(goatAI));
        assertEq(goatAI.balanceOf(address(dao)), 100_000_000_000e18);
    }
}
