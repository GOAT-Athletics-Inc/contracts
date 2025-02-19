// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";

import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";

error AccessControlUnauthorizedAccount(address account, bytes32 role);
error OwnableInvalidOwner(address account);
error OwnableUnauthorizedAccount(address account);
error ERC2612ExpiredSignature(uint256 deadline);

error InvalidAdmin(address);
error InvalidLPAddress(address);
error InvalidFeeBps(uint256);
error InvalidFeeRecipient(address);
error InvalidFeeSplitBps(uint256);
error ExceededMaxLength(uint256 maxLength, uint256 actualLength);
error MinLength(uint256 minLength);
error MismatchingArrayLengths(uint256 length1, uint256 length2);

event SetLPPair(address indexed lpPair, bool isLPPair, address indexed admin);
event SetExempt(address indexed account, bool exempt, address indexed admin);
event SetBuyFeeBps(uint256 feeBps, address indexed admin);
event SetSellFeeBps(uint256 feeBps, address indexed admin);
event SetFeeSplits(
    address[] recipients,
    uint256[] splitsBps,
    address indexed admin
);

event FeeDistributed(address indexed from, address indexed to, uint256 amount);
event Burn(address indexed account, uint256 amount);

contract GOATAITest is Test {
    GOATAI_ERC20 public goatAI;
    address public lpPair;

    address public charityWallet;
    address public treasury;
    address public dao;
    address public goatAIOps;
    address public user1;
    uint256 public user1Pk;
    address public user2;
    address public otherLPPair1;
    address public otherLPPair2;

    uint256 public charityBps;
    uint256 public treasuryBps;

    address[] public recipients;
    uint256[] public splitsBps;
    uint256 public feeBps;

    address[] public newRecipients;
    uint256[] public newSplitsBps;
    uint256 public newFeeBps;

    bytes32 public constant DEFAULT_ADMIN_ROLE = bytes32(0x0);
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    function setUp() public {
        charityWallet = makeAddr("charityWallet");
        treasury = makeAddr("treasury");
        dao = makeAddr("dao");
        goatAIOps = makeAddr("goatAIOps");
        lpPair = makeAddr("lpPair");

        otherLPPair1 = makeAddr("otherLPPair1");
        otherLPPair2 = makeAddr("otherLPPair2");
        user1 = makeAddr("user1");
        (user1, user1Pk) = makeAddrAndKey("alice");
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

        newRecipients = new address[](2);
        newSplitsBps = new uint256[](2);

        newRecipients[0] = treasury;
        newRecipients[1] = charityWallet;

        newSplitsBps[0] = 2000;
        newSplitsBps[1] = 7750;

        newFeeBps = 700;
    }

    function test_GOATAI_Constructor() public view {
        assertEq(goatAI.name(), "GOATAI");
        assertEq(goatAI.symbol(), "GOATAI");
        assertEq(goatAI.decimals(), 18);
        assertEq(
            goatAI.totalSupply(),
            1_000_000_000_000 * 10 ** goatAI.decimals()
        );

        assert(goatAI.hasRole(DEFAULT_ADMIN_ROLE, goatAIOps));
        assert(!goatAI.hasRole(DEFAULT_ADMIN_ROLE, address(this)));

        assertEq(goatAI.buyFeeBps(), 600);
        address[] memory buyRecipients = goatAI.feeRecipients();
        uint256[] memory buySplits = goatAI.feeRecipientSplits();
        assertEq(buyRecipients[0], charityWallet);
        assertEq(buySplits[0], 7000);
        assertEq(buyRecipients[1], treasury);
        assertEq(buySplits[1], 2500);
        assertEq(goatAI.feeBurnSplit(), 500);

        assertEq(goatAI.sellFeeBps(), 600);
        address[] memory sellRecipients = goatAI.feeRecipients();
        uint256[] memory sellSplits = goatAI.feeRecipientSplits();
        assertEq(sellRecipients[0], charityWallet);
        assertEq(sellSplits[0], 7000);
        assertEq(sellRecipients[1], treasury);
        assertEq(sellSplits[1], 2500);
        assertEq(goatAI.feeBurnSplit(), 500);
    }

    function test_GOATAI_FeeManagement_Constructor_CanHandleDifferentBuySellFees()
        public
    {
        GOATAI_ERC20 goatAI2 = new GOATAI_ERC20(
            address(this),
            500,
            700,
            recipients,
            splitsBps
        );

        assertEq(goatAI2.buyFeeBps(), 500);
        assertEq(goatAI2.sellFeeBps(), 700);
    }

    function test_GOATAI_FeeManagement_Constructor_ChecksInitialAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(InvalidAdmin.selector, address(0))
        );
        new GOATAI_ERC20(address(0), feeBps, feeBps, recipients, splitsBps);
    }

    function test_GOATAI_FeeManagement_Constructor_ChecksFeeParams() public {
        // 1. feeBps is > 100%
        // 1.a) buy fee
        uint256 invalidFeeBps = 100_01;
        vm.expectRevert(
            abi.encodeWithSelector(InvalidFeeBps.selector, invalidFeeBps)
        );
        new GOATAI_ERC20(
            address(this),
            invalidFeeBps,
            feeBps,
            recipients,
            splitsBps
        );
        // 1.b) sell fee
        vm.expectRevert(
            abi.encodeWithSelector(InvalidFeeBps.selector, invalidFeeBps)
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            invalidFeeBps,
            recipients,
            splitsBps
        );

        // 2. recipient is 0 address
        address[] memory invalidRecipients = recipients;
        invalidRecipients[0] = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidFeeRecipient.selector,
                invalidRecipients[0]
            )
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            invalidRecipients,
            splitsBps
        );

        // 3. another recipient is 0 address
        invalidRecipients[1] = address(0);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidFeeRecipient.selector,
                invalidRecipients[1]
            )
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            invalidRecipients,
            splitsBps
        );

        // 4. single recipient has > 100% of the fee
        uint256[] memory invalidSplits = splitsBps;
        invalidSplits[0] = 100_01;
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidFeeSplitBps.selector,
                invalidSplits[0]
            )
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            recipients,
            invalidSplits
        );

        // 5. recipient has 0 bps
        invalidSplits[0] = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidFeeSplitBps.selector,
                invalidSplits[0]
            )
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            recipients,
            invalidSplits
        );

        // 6. recipients and splits are different lengths
        invalidRecipients = new address[](0);
        invalidSplits = new uint256[](1);
        vm.expectRevert(
            abi.encodeWithSelector(MismatchingArrayLengths.selector, 0, 1)
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            invalidRecipients,
            invalidSplits
        );

        // 7. sum of recipient splits > 100%
        invalidRecipients = recipients;
        invalidSplits = splitsBps;
        invalidSplits[0] = 70000;
        invalidSplits[1] = 31000;
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidFeeSplitBps.selector,
                invalidSplits[0]
            )
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            invalidRecipients,
            invalidSplits
        );

        // 8. num recipients > 3
        invalidRecipients = new address[](6);
        invalidSplits = new uint256[](6);
        invalidRecipients[0] = charityWallet;
        invalidRecipients[1] = dao;
        invalidRecipients[2] = treasury;
        invalidRecipients[3] = address(123);
        invalidRecipients[4] = address(456);
        invalidRecipients[5] = address(789);
        invalidSplits[0] = 4000;
        invalidSplits[1] = 3000;
        invalidSplits[2] = 1500;
        invalidSplits[3] = 500;
        invalidSplits[4] = 500;
        invalidSplits[5] = 500;

        vm.expectRevert(
            abi.encodeWithSelector(ExceededMaxLength.selector, 5, 6)
        );
        new GOATAI_ERC20(
            address(this),
            feeBps,
            feeBps,
            invalidRecipients,
            invalidSplits
        );
    }

    function test_GOATAI_FeeManagement_SetBuyFeeBps_UpdateSuccess() public {
        vm.prank(goatAIOps);
        vm.expectEmit(true, true, true, true);
        emit SetBuyFeeBps(newFeeBps, goatAIOps);
        goatAI.setBuyFeeBps(newFeeBps);

        assertEq(goatAI.buyFeeBps(), 700);
    }

    function test_GOATAI_FeeManagement_SetBuyFeeBps_RevertsNotFeeManager()
        public
    {
        // fails if no role
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                FEE_MANAGER_ROLE
            )
        );
        goatAI.setBuyFeeBps(newFeeBps);

        // fails even if admin and not fee manager
        vm.prank(goatAIOps);
        goatAI.grantRole(DEFAULT_ADMIN_ROLE, user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                FEE_MANAGER_ROLE
            )
        );
        goatAI.setBuyFeeBps(newFeeBps);
    }

    function test_GOATAI_FeeManagement_SetSellFeeBps_UpdateSuccess() public {
        vm.prank(goatAIOps);
        vm.expectEmit(true, true, true, true);
        emit SetSellFeeBps(newFeeBps, goatAIOps);
        goatAI.setSellFeeBps(newFeeBps);

        assertEq(goatAI.sellFeeBps(), 700);
    }

    function test_GOATAI_FeeManagement_SetSellFee_RevertsNotFeeManager()
        public
    {
        // fails if no role
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                FEE_MANAGER_ROLE
            )
        );
        goatAI.setSellFeeBps(newFeeBps);

        // fails even if admin and not fee manager
        vm.prank(goatAIOps);
        goatAI.grantRole(DEFAULT_ADMIN_ROLE, user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                FEE_MANAGER_ROLE
            )
        );
        goatAI.setSellFeeBps(newFeeBps);
    }

    function test_GOATAI_FeeManagement_SetFeeSplits_UpdateSuccess() public {
        vm.expectEmit(true, true, true, true);
        emit SetFeeSplits(newRecipients, newSplitsBps, goatAIOps);

        vm.prank(goatAIOps);
        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        address[] memory newFeeRecipients = goatAI.feeRecipients();
        uint256[] memory newSplits = goatAI.feeRecipientSplits();
        assertEq(newFeeRecipients[0], treasury);
        assertEq(newSplits[0], 2000);
        assertEq(newFeeRecipients[1], charityWallet);
        assertEq(newSplits[1], 7750);
        assertEq(goatAI.feeBurnSplit(), 250);
    }

    function test_GOATAI_FeeManagement_SetFeeSplits_RevertsNotFeeManager()
        public
    {
        // fails if no role
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                FEE_MANAGER_ROLE
            )
        );
        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        // fails even if admin and not fee manager
        vm.prank(goatAIOps);
        goatAI.grantRole(DEFAULT_ADMIN_ROLE, user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                FEE_MANAGER_ROLE
            )
        );
        goatAI.setFeeSplits(newRecipients, newSplitsBps);
    }

    function test_GOATAI_FeeManagement_SetFeeSplits_CanSetNoRecipientsAndBurnAll()
        public
    {
        // no recipients
        newRecipients = new address[](0);
        newSplitsBps = new uint256[](0);

        vm.prank(goatAIOps);
        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        address[] memory buyRecipients = goatAI.feeRecipients();
        uint256[] memory buySplits = goatAI.feeRecipientSplits();
        assertEq(buyRecipients.length, 0);
        assertEq(buySplits.length, 0);

        assertEq(goatAI.feeBurnSplit(), 100_00);
    }

    function test_GOATAI_FeeManagement_SetFeeSplits_HandlesIncreasedArraySizes()
        public
    {
        // 1 more recipient/split than at the start
        newRecipients = new address[](3);
        newSplitsBps = new uint256[](3);

        newRecipients[0] = charityWallet;
        newRecipients[1] = dao;
        newRecipients[2] = treasury;

        newSplitsBps[0] = 4000;
        newSplitsBps[1] = 3000;
        newSplitsBps[2] = 2500;

        vm.prank(goatAIOps);
        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        address[] memory buyRecipients = goatAI.feeRecipients();
        uint256[] memory buySplits = goatAI.feeRecipientSplits();
        assertEq(buyRecipients[0], charityWallet);
        assertEq(buySplits[0], 4000);
        assertEq(buyRecipients[1], dao);
        assertEq(buySplits[1], 3000);
        assertEq(buyRecipients[2], treasury);
        assertEq(buySplits[2], 2500);
        assertEq(goatAI.feeBurnSplit(), 500);
    }

    function test_GOATAI_FeeManagement_SetFeeSplits_HandlesReducedArraySizes()
        public
    {
        // Change buy fee structure to have 1 less recipient/split
        newRecipients = new address[](1);
        newSplitsBps = new uint256[](1);

        newRecipients[0] = charityWallet;
        newSplitsBps[0] = 9500;

        // 1 less recipient/split than at the start
        vm.prank(goatAIOps);
        goatAI.setFeeSplits(newRecipients, newSplitsBps);

        address[] memory newFeeRecipients = goatAI.feeRecipients();
        uint256[] memory buySplits = goatAI.feeRecipientSplits();
        assertEq(newFeeRecipients[0], charityWallet);
        assertEq(buySplits[0], 9500);
        assertEq(goatAI.feeBurnSplit(), 500);
    }

    function test_GOATAI_FeeManagement_SetFeeBps_RevertsInvalidBps() public {
        // buy fee is > 100%
        vm.prank(goatAIOps);
        vm.expectRevert(abi.encodeWithSelector(InvalidFeeBps.selector, 100_01));
        goatAI.setBuyFeeBps(100_01);

        // sell fee is > 100%
        vm.prank(goatAIOps);
        vm.expectRevert(abi.encodeWithSelector(InvalidFeeBps.selector, 100_01));
        goatAI.setSellFeeBps(100_01);
    }

    function test_GOATAI_FeeManagement_SetFeeSplits_RevertsInvalidSplits()
        public
    {
        // 1. recipient is 0 address
        address[] memory invalidRecipients = recipients;
        invalidRecipients[0] = address(0);
        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidFeeRecipient.selector, address(0))
        );
        goatAI.setFeeSplits(invalidRecipients, splitsBps);

        // 2. another recipient is 0 address
        invalidRecipients[1] = address(0);
        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidFeeRecipient.selector, address(0))
        );
        goatAI.setFeeSplits(invalidRecipients, splitsBps);

        // 3. recipient has > 100% of the fee
        uint256[] memory invalidSplits = splitsBps;
        invalidSplits[0] = 100_01;
        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidFeeSplitBps.selector, 100_01)
        );
        goatAI.setFeeSplits(recipients, invalidSplits);

        // 4. recipient has 0 bps
        invalidSplits[0] = 0;
        vm.prank(goatAIOps);
        vm.expectRevert(abi.encodeWithSelector(InvalidFeeSplitBps.selector, 0));
        goatAI.setFeeSplits(recipients, invalidSplits);

        // 5. recipients and splits are different lengths
        invalidRecipients = new address[](0);
        invalidSplits = new uint256[](1);
        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(MismatchingArrayLengths.selector, 0, 1)
        );
        goatAI.setFeeSplits(invalidRecipients, invalidSplits);

        // 6. sum of recipient splits > 100%
        invalidRecipients = recipients;
        invalidSplits = splitsBps;
        invalidSplits[0] = 70_00;
        invalidSplits[1] = 31_00;

        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidFeeSplitBps.selector, 101_00)
        );
        goatAI.setFeeSplits(invalidRecipients, invalidSplits);

        // 7. num recipients > 3
        invalidRecipients = new address[](6);
        invalidSplits = new uint256[](6);
        invalidRecipients[0] = charityWallet;
        invalidRecipients[1] = dao;
        invalidRecipients[2] = treasury;
        invalidRecipients[3] = address(123);
        invalidRecipients[4] = address(456);
        invalidRecipients[5] = address(789);
        invalidSplits[0] = 40_00;
        invalidSplits[1] = 20_00;
        invalidSplits[2] = 15_00;
        invalidSplits[3] = 10_00;
        invalidSplits[4] = 10_00;
        invalidSplits[5] = 5_00;

        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(ExceededMaxLength.selector, 5, 6)
        );
        goatAI.setFeeSplits(invalidRecipients, invalidSplits);
    }

    // FM.LP_PAIR
    function test_GOATAI_FeeManagement_SetAndRemoveLiquidityPair() public {
        vm.expectEmit(true, true, true, true);
        emit SetLPPair(otherLPPair1, true, goatAIOps);

        vm.prank(goatAIOps);
        goatAI.setLPPair(otherLPPair1, true);
        assert(goatAI.isLPPair(otherLPPair1));
        assert(!goatAI.isLPPair(otherLPPair2));

        vm.expectEmit(true, true, true, true);
        emit SetLPPair(otherLPPair2, true, goatAIOps);

        vm.prank(goatAIOps);
        goatAI.setLPPair(otherLPPair2, true);
        assert(goatAI.isLPPair(otherLPPair2));
        assert(goatAI.isLPPair(otherLPPair1));

        // set again to test if it reverts
        vm.prank(goatAIOps);
        goatAI.setLPPair(otherLPPair1, true);
        assert(goatAI.isLPPair(otherLPPair1));
        assert(goatAI.isLPPair(otherLPPair2));

        vm.expectEmit(true, true, true, true);
        emit SetLPPair(otherLPPair1, false, goatAIOps);

        vm.prank(goatAIOps);
        goatAI.setLPPair(otherLPPair1, false);
        assert(!goatAI.isLPPair(otherLPPair1));
        assert(goatAI.isLPPair(otherLPPair2));

        vm.prank(goatAIOps);
        goatAI.setLPPair(otherLPPair2, false);
        assert(!goatAI.isLPPair(otherLPPair1));
        assert(!goatAI.isLPPair(otherLPPair2));

        // remove again to test if it reverts
        vm.prank(goatAIOps);
        goatAI.setLPPair(otherLPPair2, false);
        assert(!goatAI.isLPPair(otherLPPair1));
        assert(!goatAI.isLPPair(otherLPPair2));
    }

    function test_GOATAI_FeeManagement_SetRemoveLiquidityPair_RevertsZeroAddress()
        public
    {
        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidLPAddress.selector, address(0))
        );
        goatAI.setLPPair(address(0), true);
    }

    function test_GOATAI_FeeManagement_SetRemoveLiquidityPair_RevertsNotDefaultAdmin()
        public
    {
        // fails if no role
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        goatAI.setLPPair(otherLPPair1, true);

        // fails if fee manager and not default admin
        vm.prank(goatAIOps);
        goatAI.grantRole(FEE_MANAGER_ROLE, user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        goatAI.setLPPair(otherLPPair1, true);
    }

    // FM.EXEMPTIONS
    function test_GOATAI_FeeManagement_SetExempt() public {
        vm.expectEmit(true, true, true, true);
        emit SetExempt(charityWallet, true, goatAIOps);

        address[] memory accounts = new address[](1);
        accounts[0] = charityWallet;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, true);
        assert(goatAI.isExempt(charityWallet));

        vm.expectEmit(true, true, true, true);
        emit SetExempt(treasury, true, goatAIOps);

        accounts = new address[](1);
        accounts[0] = treasury;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, true);
        assert(goatAI.isExempt(treasury));

        vm.expectEmit(true, true, true, true);
        emit SetExempt(dao, true, goatAIOps);

        accounts = new address[](1);
        accounts[0] = dao;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, true);
        assert(goatAI.isExempt(dao));

        vm.expectEmit(true, true, true, true);
        emit SetExempt(charityWallet, false, goatAIOps);

        accounts = new address[](1);
        accounts[0] = charityWallet;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, false);
        assert(!goatAI.isExempt(charityWallet));

        vm.expectEmit(true, true, true, true);
        emit SetExempt(treasury, false, goatAIOps);

        accounts = new address[](1);
        accounts[0] = treasury;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, false);
        assert(!goatAI.isExempt(treasury));

        vm.expectEmit(true, true, true, true);
        emit SetExempt(dao, false, goatAIOps);

        accounts = new address[](1);
        accounts[0] = dao;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, false);
        assert(!goatAI.isExempt(dao));
    }

    function test_GOATAI_FeeManagement_SetExempt_HandlesMultipleAddresses()
        public
    {
        address[] memory accounts = new address[](3);
        accounts[0] = charityWallet;
        accounts[1] = dao;
        accounts[2] = treasury;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, true);
        assert(goatAI.isExempt(charityWallet));
        assert(goatAI.isExempt(dao));
        assert(goatAI.isExempt(treasury));

        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, false);
        assert(!goatAI.isExempt(charityWallet));
        assert(!goatAI.isExempt(dao));
        assert(!goatAI.isExempt(treasury));

        accounts = new address[](2);
        accounts[0] = charityWallet;
        accounts[1] = dao;
        vm.prank(goatAIOps);
        goatAI.setExempt(accounts, true);
        assert(goatAI.isExempt(charityWallet));
        assert(goatAI.isExempt(dao));
        assert(!goatAI.isExempt(treasury));
    }

    function test_GOATAI_FeeManagement_SetExempt_RevertsNotDefaultAdmin()
        public
    {
        // fails if no role
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        address[] memory exemptAccounts = new address[](1);
        exemptAccounts[0] = charityWallet;
        goatAI.setExempt(exemptAccounts, true);

        // fails if fee manager and not default admin
        vm.prank(goatAIOps);
        goatAI.grantRole(FEE_MANAGER_ROLE, user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        goatAI.setExempt(exemptAccounts, true);
    }

    function test_GOATAI_FeeManagement_SetExempt_RevertsEmptyArray() public {
        vm.prank(goatAIOps);
        vm.expectRevert(abi.encodeWithSelector(MinLength.selector, 1));
        address[] memory exemptAccounts = new address[](0);
        goatAI.setExempt(exemptAccounts, true);
    }

    function test_GOATAI_FeeManagement_SetExempt_RevertsTooManyExemptions() public {
        vm.prank(goatAIOps);
        address[] memory exemptAccounts = new address[](50);
        for (uint256 i = 0; i < 50; i++) {
            exemptAccounts[i] = makeAddr("exempt");
        }
        vm.expectRevert(abi.encodeWithSelector(ExceededMaxLength.selector, 20, 50));
        goatAI.setExempt(exemptAccounts, true);
    }

    function test_GOATAI_GrantRevokeRole() public {
        vm.prank(goatAIOps);
        goatAI.grantRole(FEE_MANAGER_ROLE, dao);
        assert(goatAI.hasRole(FEE_MANAGER_ROLE, dao));
        assert(!goatAI.hasRole(DEFAULT_ADMIN_ROLE, dao));

        vm.prank(goatAIOps);
        goatAI.revokeRole(FEE_MANAGER_ROLE, goatAIOps);
        assert(!goatAI.hasRole(FEE_MANAGER_ROLE, goatAIOps));

        vm.prank(goatAIOps);
        goatAI.grantRole(DEFAULT_ADMIN_ROLE, dao);
        assert(goatAI.hasRole(DEFAULT_ADMIN_ROLE, dao));

        vm.prank(goatAIOps);
        goatAI.revokeRole(DEFAULT_ADMIN_ROLE, goatAIOps);
        assert(!goatAI.hasRole(DEFAULT_ADMIN_ROLE, goatAIOps));
    }

    function test_GOATAI_GrantRole_RevertsNotDefaultAdmin() public {
        // fails if no role
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        goatAI.grantRole(DEFAULT_ADMIN_ROLE, user1);

        // fails if fee manager and not default admin
        vm.prank(goatAIOps);
        goatAI.grantRole(FEE_MANAGER_ROLE, user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        goatAI.grantRole(DEFAULT_ADMIN_ROLE, user1);
    }

    function test_GOATAI_RevokeRole_RevertsNotDefaultAdmin() public {
        // fails if no role
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        goatAI.grantRole(DEFAULT_ADMIN_ROLE, user1);

        // fails if fee manager and not default admin
        vm.prank(goatAIOps);
        goatAI.grantRole(FEE_MANAGER_ROLE, user1);
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                user1,
                DEFAULT_ADMIN_ROLE
            )
        );
        goatAI.revokeRole(DEFAULT_ADMIN_ROLE, user1);
    }

    function test_GOATAI_Transfer_ShouldDelegateVotesForNewRecipient() public {
        uint256 amount = 1000;

        vm.prank(goatAIOps);
        goatAI.transfer(user1, amount);

        assertEq(goatAI.balanceOf(user1), amount);
        assertEq(goatAI.getVotes(user1), amount);

        vm.prank(user1);
        goatAI.transfer(user2, amount / 2);
        assertEq(goatAI.balanceOf(user1), amount / 2);
        assertEq(goatAI.getVotes(user1), amount / 2);
        assertEq(goatAI.balanceOf(user2), amount / 2);
        assertEq(goatAI.getVotes(user2), amount / 2);
    }

    function test_GOATAI_ClockMode() public view {
        assertEq(goatAI.CLOCK_MODE(), "mode=timestamp");
    }

    function test_GOATAI_Clock_TimestampMode() public {
        uint256 future = block.timestamp + 1 days;
        vm.warp(future);
        assertEq(goatAI.clock(), future);
    }

    function test_InitialNonceIsZero() public view {
        assertEq(goatAI.nonces(user1), 0, "Initial nonce should be zero");
    }

    function test_NonceIncrementWithPermit() public {
        uint256 amount = 1000e18;
        uint256 deadline = block.timestamp + 1 days;

        // Generate permit signature
        bytes32 domainSeparator = goatAI.DOMAIN_SEPARATOR();
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        keccak256(
                            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                        ),
                        user1,
                        lpPair,
                        amount,
                        0, // Initial nonce
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1Pk, permitHash);

        // Execute permit
        goatAI.permit(user1, lpPair, amount, deadline, v, r, s);

        // Verify nonce increased
        assertEq(
            goatAI.nonces(user1),
            1,
            "Nonce should increment after permit"
        );
    }

    function test_RevertExpiredPermit() public {
        uint256 amount = 1000e18;
        uint256 deadline = block.timestamp - 1; // Expired deadline

        bytes32 domainSeparator = goatAI.DOMAIN_SEPARATOR();
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                keccak256(
                    abi.encode(
                        keccak256(
                            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                        ),
                        user1,
                        lpPair,
                        amount,
                        0, // Initial nonce
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(user1Pk, permitHash);

        // Expect revert for expired permit
        vm.expectRevert(
            abi.encodeWithSelector(ERC2612ExpiredSignature.selector, 0)
        );
        goatAI.permit(user1, lpPair, amount, deadline, v, r, s);

        // Verify nonce didn't change
        assertEq(
            goatAI.nonces(user1),
            0,
            "Nonce should not change on failed permit"
        );
    }
}
