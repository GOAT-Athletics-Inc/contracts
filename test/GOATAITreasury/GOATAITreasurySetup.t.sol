// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Router01} from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router01.sol";

import {GOATAITreasury} from "../../contracts/GOATAITreasury.sol";
import {GOATAI_ERC20} from "../../contracts/GOATAI_ERC20.sol";
import {MockWrappedEth} from "../utils/MockWrappedEth.sol";

contract GOATAITreasurySetupTest is Test {
    ERC1967Proxy proxy;
    GOATAI_ERC20 public goatAI;
    GOATAITreasury public goataiTreasury;

    address public lpPair;
    address factory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
    address router = 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24;

    MockWrappedEth weth;
    ERC20 USDC;

    address pair;

    uint256 forkId;

    address public treasuryAdmin;
    address public goatAIOps;
    address public charityWallet;
    address public executor;
    address public randomUser;

    address public initialExecutor;
    GOATAITreasury cfImplementation;
    ERC1967Proxy cfProxy;

    function setUp() public virtual {
        forkId = vm.createFork("https://mainnet.base.org");
        vm.selectFork(forkId);

        vm.deal(address(this), 100 ether);

        weth = MockWrappedEth(0x4200000000000000000000000000000000000006);
        USDC = ERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

        goatAIOps = makeAddr("goatAIOps");
        charityWallet = makeAddr("charityWallet");
        executor = makeAddr("executor");
        treasuryAdmin = makeAddr("treasuryAdmin");
        randomUser = makeAddr("randomUser");

        initialExecutor = executor;

        cfImplementation = new GOATAITreasury();
        // Deploy the proxy and call initialize via the proxy
        cfProxy = new ERC1967Proxy(
            address(cfImplementation),
            abi.encodeWithSelector(
                GOATAITreasury.initialize.selector,
                // Pass initialization arguments
                charityWallet, // recipient
                weth, // base token - GOATAI does not exist yet, so putting temporary one
                USDC, // output token
                router,
                initialExecutor
            )
        );
        // Cast proxy to interact with it like the implementation
        goataiTreasury = GOATAITreasury(address(cfProxy));

        uint256 feeBps = 600;

        address[] memory recipients = new address[](2);
        recipients[0] = charityWallet;
        recipients[1] = goatAIOps;

        uint256[] memory splitsBps = new uint256[](2);
        splitsBps[0] = 7000;
        splitsBps[1] = 2500;

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

        IUniswapV2Router01(router).addLiquidityETH{value: 15 ether}(
            address(goatAI),
            liquidityGOATAI, // amountTokenDesired
            liquidityGOATAI, // amountTokenMin
            15 ether, // amountETHMin
            goatAIOps, // recipient of LP tokens
            block.timestamp + 1 // deadline
        );

        goatAI.setLPPair(lpPair, true);

        address[] memory exemptAccounts = new address[](1);
        exemptAccounts[0] = address(goataiTreasury);

        goatAI.setExempt(exemptAccounts, true);

        vm.prank(charityWallet);
        goataiTreasury.setBaseToken(address(goatAI));
    }
}
