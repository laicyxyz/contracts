// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Laicy} from "../src/Laicy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IUniswapV3Factory
 * @dev Interface for the Uniswap V3 Factory
 */
interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

/**
 * @title IUniswapV3Pool
 * @dev Interface for the Uniswap V3 Pool
 */
interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
}

/**
 * @title INonfungiblePositionManager
 * @dev Interface for the Uniswap V3 Nonfungible Position Manager
 */
interface INonfungiblePositionManager {
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
}

/**
 * @title IWETH9
 * @dev Interface for WETH9
 */
interface IWETH9 is IERC20 {
    function deposit() external payable;
}

/**
 * @title LaicyDeployerScript
 * @dev A script that deploys Laicy token, creates a Uniswap V3 pool, and adds liquidity
 */
contract LaicyDeployerScript is Script {
    // Constants
    uint24 public constant POOL_FEE = 10000; // 1% fee tier
    uint160 public constant INITIAL_SQRT_PRICE = 1000000; // Corresponds to 0.000001 WETH per LAICY

    // Mainnet addresses
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy Laicy token
        Laicy laicy = new Laicy();
        address laicyToken = address(laicy);

        // Log deployment
        console.log("Laicy token deployed at:", laicyToken);

        // Create Uniswap V3 pool
        address token0 = laicyToken < WETH ? laicyToken : WETH;
        address token1 = laicyToken < WETH ? WETH : laicyToken;

        address pool = IUniswapV3Factory(UNISWAP_V3_FACTORY).createPool(token0, token1, POOL_FEE);

        // Log pool creation
        console.log("Uniswap V3 pool created at:", pool);

        // Initialize pool with price
        IUniswapV3Pool(pool).initialize(INITIAL_SQRT_PRICE);
        console.log("Pool initialized with price 0.000001 WETH per LAICY");

        // Get the full balance of Laicy tokens
        uint256 laicyBalance = laicy.balanceOf(msg.sender);

        // Calculate the amount of WETH needed based on the price
        // Price is 0.000001 WETH per LAICY
        uint256 wethAmount = (laicyBalance * 1e12) / 1e18; // 0.000001 * laicyBalance

        // Log liquidity amounts
        console.log("Adding liquidity with:");
        console.log("- LAICY amount:", laicyBalance);
        console.log("- WETH amount:", wethAmount);

        // Approve tokens for position manager
        laicy.approve(NONFUNGIBLE_POSITION_MANAGER, type(uint256).max);
        IWETH9(WETH).approve(NONFUNGIBLE_POSITION_MANAGER, type(uint256).max);

        // Determine token0 and token1
        bool isLaicyToken0 = laicyToken < WETH;

        // Set up mint parameters
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: isLaicyToken0 ? laicyToken : WETH,
            token1: isLaicyToken0 ? WETH : laicyToken,
            fee: POOL_FEE,
            tickLower: -887220, // Minimum tick for full range
            tickUpper: 887220, // Maximum tick for full range
            amount0Desired: isLaicyToken0 ? laicyBalance : wethAmount,
            amount1Desired: isLaicyToken0 ? wethAmount : laicyBalance,
            amount0Min: 0,
            amount1Min: 0,
            recipient: msg.sender,
            deadline: block.timestamp + 15 minutes
        });

        // Mint position
        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) =
            INonfungiblePositionManager(NONFUNGIBLE_POSITION_MANAGER).mint(params);

        // Log position details
        console.log("Position created:");
        console.log("- Token ID:", tokenId);
        console.log("- Liquidity:", liquidity);
        console.log("- Amount0 used:", amount0);
        console.log("- Amount1 used:", amount1);

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
