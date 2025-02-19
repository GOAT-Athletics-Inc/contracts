// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IVotes} from "@openzeppelin/contracts/governance/utils/IVotes.sol";

import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";
import {TestGOATAIGovernor} from "../utils/TestGOATAIGovernor.sol";

contract GOATAIVotesTest is Test {
    GOATAI_ERC20 public goatAI;
    TestGOATAIGovernor public dao;

    address public lpPair;
    address public charityWallet;
    address public treasury;
    address public goatAIOps;
    address public marketing;
    address public user1;
    address public user2;

    uint256 public charityBps;
    uint256 public treasuryBps;

    address[] public recipients;
    uint256[] public splitsBps;
    uint256 public feeBps;

    address[] public newRecipients;
    uint256[] public newSplitsBps;
    uint256 public newFeeBps;

    TimelockController timelock;

    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0x0);
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    function setUp() public {
        charityWallet = makeAddr("charityWallet");
        treasury = makeAddr("treasury");
        goatAIOps = makeAddr("goatAIOps");
        marketing = makeAddr("marketing");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

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

        vm.prank(goatAIOps);
        goatAI.transfer(treasury, 10_000_000_000e18);
        vm.prank(treasury);
        goatAI.delegate(treasury);

        vm.prank(goatAIOps);
        goatAI.transfer(user1, 1_000_000_000e18);
        vm.prank(user1);
        goatAI.delegate(user1);

        vm.prank(goatAIOps);
        goatAI.transfer(user2, 1_000_000_000e18);
        vm.prank(user2);
        goatAI.delegate(user2);

        newFeeBps = 700;

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

        vm.prank(goatAIOps);
        goatAI.transfer(address(dao), 150_000_000_000e18);

        assert(timelock.hasRole(DEFAULT_ADMIN_ROLE, goatAIOps));

        bytes32 PROPOSER_ROLE = timelock.PROPOSER_ROLE();
        bytes32 EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();

        vm.prank(goatAIOps);
        timelock.grantRole(PROPOSER_ROLE, address(dao));

        vm.prank(goatAIOps);
        timelock.grantRole(EXECUTOR_ROLE, address(dao));
    }

    function test_GOATAI_DAO_proposeChangeFeeSplits_Passes() public {
        vm.prank(goatAIOps);
        goatAI.grantRole(FEE_MANAGER_ROLE, address(timelock));

        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory calldatas = new bytes[](1);

        targets[0] = address(goatAI);

        values[0] = 0;

        newRecipients = new address[](2);
        newSplitsBps = new uint256[](2);

        newRecipients[0] = charityWallet;
        newRecipients[1] = marketing;

        newSplitsBps[0] = 45_00;
        newSplitsBps[1] = 45_00;

        calldatas[0] = abi.encodeWithSelector(
            GOATAI_ERC20.setFeeSplits.selector,
            newRecipients,
            newSplitsBps
        );

        string memory description = "Proposal to change fee";
        bytes32 descriptionHash = keccak256(abi.encodePacked(description));

        vm.warp(block.timestamp + 3 days);

        vm.prank(goatAIOps);
        uint256 proposalId = dao.propose(
            targets,
            values,
            calldatas,
            description
        );

        // Wait for voting delay from proposal, as specified in Governor contract
        vm.warp(block.timestamp + dao.votingDelay() + 1);

        vm.prank(user1);
        dao.castVote(proposalId, 1);

        vm.prank(user2);
        dao.castVote(proposalId, 1);

        vm.prank(goatAIOps);
        dao.castVote(proposalId, 1);

        vm.prank(charityWallet);
        dao.castVote(proposalId, 1);

        vm.prank(treasury);
        dao.castVote(proposalId, 1);

        // Wait for voting period to end, as specified in Governor contract
        vm.warp(block.timestamp + dao.votingPeriod() + 1);
        vm.prank(goatAIOps);
        dao.queue(targets, values, calldatas, descriptionHash);

        // Wait for timelock delay, as specified in TimelockController contract
        vm.warp(block.timestamp + timelock.getMinDelay());
        vm.prank(goatAIOps);
        dao.execute(targets, values, calldatas, descriptionHash);

        address[] memory _newFeeRecipients = goatAI.feeRecipients();
        uint256[] memory _newFeeRecipientSplits = goatAI.feeRecipientSplits();

        assertEq(_newFeeRecipients[0], charityWallet);
        assertEq(_newFeeRecipients[1], marketing);

        assertEq(_newFeeRecipientSplits[0], 45_00);
        assertEq(_newFeeRecipientSplits[1], 45_00);

        assertEq(goatAI.feeBurnSplit(), 10_00);
    }

    // transfer admin to dao or another multisig???

    // TODO: DAO can spend its own tokens, if sent
    // TODO: DAO can swap its own tokens
    // TODO: DAO can burn its own tokens
    // TODO: special ops team can cancel proposal
}
