// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {GOATAITreasury} from "../../contracts/GOATAITreasury.sol";
import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";
import {GOATAITreasurySetupTest} from "./GOATAITreasurySetup.t.sol";

error AccessControlUnauthorizedAccount(address account, bytes32 role);

error AdminCannotRenounceRole();
error ZeroAddress();
error InvalidTokenAddress();

event RoleGranted(
    bytes32 indexed role,
    address indexed account,
    address indexed sender
);
event RoleRevoked(
    bytes32 indexed role,
    address indexed account,
    address indexed sender
);
event SetRecipient(address indexed recipient);
event SetBaseToken(address indexed baseToken);
event SetOutputToken(address indexed outputToken);
event SetUniswapV2Router(address indexed uniswapV2Router);

contract GOATAITreasuryWithdrawTest is Test, GOATAITreasurySetupTest {
    bytes32 constant DEFAULT_ADMIN_ROLE = bytes32(0x0);
    bytes32 constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");

    function setUp() public override {
        super.setUp();
    }

    function test_GOATAITreasury_Initializer() public view {
        assertEq(goataiTreasury.recipient(), charityWallet);
        assertEq(goataiTreasury.baseToken(), address(goatAI));
        assertEq(goataiTreasury.outputToken(), address(USDC));
        assertEq(goataiTreasury.uniswapV2Router(), router);
        assert(goataiTreasury.hasRole(DEFAULT_ADMIN_ROLE, charityWallet));
        assert(goataiTreasury.hasRole(EXECUTOR_ROLE, charityWallet));
        assert(goataiTreasury.hasRole(EXECUTOR_ROLE, executor));

        assert(!goataiTreasury.hasRole(DEFAULT_ADMIN_ROLE, address(this)));
    }

    function test_GOATAITreasury_Initializer_ChecksRecipientAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                address(0), // recipient
                address(goatAI), // base token
                address(USDC), // output token
                router,
                initialExecutor
            )
        );
    }

    function test_GOATAITreasury_Initializer_ChecksBaseTokenAddress() public {
        // passing 0 address
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                charityWallet, // recipient
                address(0), // base token
                address(USDC), // output token
                router,
                initialExecutor
            )
        );

        // passing a contract address that is not an ERC20
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                charityWallet, // recipient
                address(this), // base token
                address(USDC), // output token
                router,
                initialExecutor
            )
        );

        // passing an EOA, fails call without specific selector
        vm.expectRevert();
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                charityWallet, // recipient
                charityWallet, // base token
                address(USDC), // output token
                router,
                initialExecutor
            )
        );
    }

    function test_GOATAITreasury_Initializer_ChecksOutputTokenAddress() public {
        // passing 0 address
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                charityWallet, // recipient
                address(goatAI), // base token
                address(0), // output token
                router,
                initialExecutor
            )
        );

        // passing a contract address that is not an ERC20
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                charityWallet, // recipient
                address(goatAI), // base token
                address(this), // output token
                router,
                initialExecutor
            )
        );

        // passing an EOA, fails call without specific selector
        vm.expectRevert();
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                charityWallet, // recipient
                address(goatAI), // base token
                router,
                initialExecutor
            )
        );
    }

    function test_GOATAITreasury_SetRecipient() public {
        assertEq(goataiTreasury.recipient(), charityWallet);
        assertEq(goataiTreasury.hasRole(EXECUTOR_ROLE, charityWallet), true);
        assertEq(
            goataiTreasury.hasRole(DEFAULT_ADMIN_ROLE, charityWallet),
            true
        );

        vm.expectEmit(true, true, true, true);
        emit SetRecipient(treasuryAdmin);

        vm.prank(charityWallet);
        goataiTreasury.setRecipient(treasuryAdmin);

        assertEq(goataiTreasury.recipient(), treasuryAdmin);
        assertEq(goataiTreasury.hasRole(EXECUTOR_ROLE, treasuryAdmin), true);
        assertEq(
            goataiTreasury.hasRole(DEFAULT_ADMIN_ROLE, treasuryAdmin),
            true
        );

        // retains previous roles
        assertEq(goataiTreasury.hasRole(EXECUTOR_ROLE, charityWallet), true);
        assertEq(
            goataiTreasury.hasRole(DEFAULT_ADMIN_ROLE, charityWallet),
            true
        );
    }

    function test_GOATAITreasury_SetRecipient_RevertsZeroAddress() public {
        vm.prank(charityWallet);
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        goataiTreasury.setRecipient(address(0));
    }

    function test_GOATAITreasury_SetRecipient_RevertsNotAdmin() public {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                executor,
                0x0
            )
        );
        goataiTreasury.setRecipient(randomUser);

        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x0
            )
        );
        goataiTreasury.setRecipient(randomUser);
    }

    function test_GOATAITreasury_SetBaseToken() public {
        assertEq(goataiTreasury.baseToken(), address(goatAI));

        vm.expectEmit(true, true, true, true);
        emit SetBaseToken(address(USDC));

        vm.prank(charityWallet);
        goataiTreasury.setBaseToken(address(USDC));

        assertEq(goataiTreasury.baseToken(), address(USDC));
    }

    function test_GOATAITreasury_SetBaseToken_RevertsIfInvalid() public {
        // passing 0 address
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        vm.prank(charityWallet);
        goataiTreasury.setBaseToken(address(0));

        // passing a contract address that is not an ERC20
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        vm.prank(charityWallet);
        goataiTreasury.setBaseToken(router);

        // passing an EOA, fails call without specific selector
        vm.expectRevert();
        vm.prank(charityWallet);
        goataiTreasury.setBaseToken(charityWallet);
    }

    function test_GOATAITreasury_SetBaseToken_RevertsNotAdmin() public {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                executor,
                0x0
            )
        );
        address randomToken = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        goataiTreasury.setBaseToken(randomToken);

        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x0
            )
        );
        goataiTreasury.setBaseToken(randomToken);
    }

    function test_GOATAITreasury_SetOutputToken() public {
        assertEq(goataiTreasury.outputToken(), address(USDC));

        address EURC = 0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42;

        vm.expectEmit(true, true, true, true);
        emit SetOutputToken(EURC);

        vm.prank(charityWallet);
        goataiTreasury.setOutputToken(address(EURC));

        assertEq(goataiTreasury.outputToken(), address(EURC));
    }

    function test_GOATAITreasury_SetOutputToken_RevertsIfInvalid() public {
        // passing 0 address
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        vm.prank(charityWallet);
        goataiTreasury.setOutputToken(address(0));

        // passing a contract address that is not an ERC20
        vm.expectRevert(abi.encodeWithSelector(InvalidTokenAddress.selector));
        vm.prank(charityWallet);
        goataiTreasury.setOutputToken(router);

        // passing an EOA, fails call without specific selector
        vm.expectRevert();
        vm.prank(charityWallet);
        goataiTreasury.setOutputToken(charityWallet);
    }

    function test_GOATAITreasury_SetOutputToken_RevertsNotAdmin() public {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                executor,
                0x0
            )
        );
        address randomToken = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        goataiTreasury.setOutputToken(randomToken);

        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x0
            )
        );
        goataiTreasury.setOutputToken(randomToken);
    }

    function test_GOATAITreasury_SetUniswapV2Router() public {
        assertEq(goataiTreasury.uniswapV2Router(), router);

        address newRouter = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

        vm.expectEmit(true, true, true, true);
        emit SetUniswapV2Router(newRouter);

        vm.prank(charityWallet);
        goataiTreasury.setUniswapV2Router(newRouter);

        assertEq(goataiTreasury.uniswapV2Router(), newRouter);
    }

    function test_GOATAITreasury_SetUniswapV2Router_RevertsZeroAddress()
        public
    {
        vm.expectRevert(abi.encodeWithSelector(ZeroAddress.selector));
        vm.prank(charityWallet);
        goataiTreasury.setUniswapV2Router(address(0));
    }

    function test_GOATAITreasury_SetUniswapV2Router_RevertsNotAdmin() public {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                executor,
                0x0
            )
        );
        goataiTreasury.setUniswapV2Router(randomUser);

        address maliciousRouter = address(123);

        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x0
            )
        );
        goataiTreasury.setUniswapV2Router(maliciousRouter);
    }

    function test_GOATAITreasury_GrantRole() public {
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(EXECUTOR_ROLE, randomUser, charityWallet);
        vm.prank(charityWallet);
        goataiTreasury.grantRole(EXECUTOR_ROLE, randomUser);
        assertEq(goataiTreasury.hasRole(EXECUTOR_ROLE, randomUser), true);
    }

    function test_GOATAITreasury_GrantRole_RevertsIfNotAdmin() public {
        vm.prank(executor);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                executor,
                0x0
            )
        );
        goataiTreasury.grantRole(EXECUTOR_ROLE, randomUser);
    }

    function test_GOATAITreasury_RevokeRole() public {
        assertEq(goataiTreasury.hasRole(EXECUTOR_ROLE, executor), true);

        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(EXECUTOR_ROLE, executor, charityWallet);
        vm.prank(charityWallet);
        goataiTreasury.revokeRole(EXECUTOR_ROLE, executor);
        assertEq(goataiTreasury.hasRole(EXECUTOR_ROLE, executor), false);
    }

    function test_GOATAITreasury_RevokeRole_RevertsIfNotAdmin() public {
        vm.prank(randomUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                AccessControlUnauthorizedAccount.selector,
                randomUser,
                0x0
            )
        );
        goataiTreasury.revokeRole(EXECUTOR_ROLE, charityWallet);
    }

    function test_GOATAITreasury_RenounceRole_ErrorsIfAdmin() public {
        vm.prank(goatAIOps);
        vm.expectRevert(
            abi.encodeWithSelector(AdminCannotRenounceRole.selector)
        );
        goataiTreasury.renounceRole(DEFAULT_ADMIN_ROLE, goatAIOps);
    }

    function test_GOATAITreasury_RenounceRole_AllowedIfOtherRole() public {
        vm.prank(executor);
        goataiTreasury.renounceRole(EXECUTOR_ROLE, executor);
        assert(!goataiTreasury.hasRole(EXECUTOR_ROLE, executor));
    }
}
