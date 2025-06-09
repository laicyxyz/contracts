// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Laicy} from "./Laicy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "./libraries/TickMath.sol";
// import {IUniswapV3Factory} from "lib/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
// import {IUniswapV3Pool} from "lib/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
// import {INonfungiblePositionManager} from "lib/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
}

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

contract LaicyDeployer {
    uint24 public constant POOL_FEE = 10000; // 1% fee tier

    address public immutable laicyToken;
    address public immutable weth;
    address public immutable uniswapV3Factory;
    address public immutable nonfungiblePositionManager;
    address public immutable uniswapV3Pool;

    uint256 internal constant Q96 = 0x1000000000000000000000000;

    event LaicyDeployed(address indexed laicyToken);
    event PoolCreated(address indexed pool, address indexed token0, address indexed token1, uint24 fee);

    constructor(address _weth, address _uniswapV3Factory, address _nonfungiblePositionManager) {
        weth = _weth;
        uniswapV3Factory = _uniswapV3Factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;

        laicyToken = address(new Laicy());
        emit LaicyDeployed(laicyToken);

        // The Laicy constructor mints all tokens to msg.sender (which is this contract during construction)
        // Verify tokens were minted to this contract
        uint256 totalSupply = IERC20(laicyToken).balanceOf(address(this));
        require(totalSupply > 0, "No tokens minted");

        uint256 initPrice = 25_000_000; // lAIcy per WETH
        address token0 = weth;
        address token1 = laicyToken;
        uint160 initSqrtPriceX96 = uint160(_sqrt(initPrice * Q96) * _sqrt(Q96));
        if (laicyToken < weth) {
            token0 = laicyToken;
            token1 = weth;
            initSqrtPriceX96 = uint160(_sqrt(Q96 / initPrice) * _sqrt(Q96));
        }

        // go to nearest tick and back to ensure it's on a tick boundary
        // allows us to provide liquidity with 100% lAIcy and 0 WETH
        int24 nearestTick = TickMath.getTickAtSqrtRatio(initSqrtPriceX96);
        initSqrtPriceX96 = TickMath.getSqrtRatioAtTick(nearestTick);

        address pool = IUniswapV3Factory(uniswapV3Factory).createPool(token0, token1, POOL_FEE);
        uniswapV3Pool = pool;
        emit PoolCreated(pool, token0, token1, POOL_FEE);

        IUniswapV3Pool(pool).initialize(initSqrtPriceX96);
        _addLiquidity(initSqrtPriceX96);
    }

    function _addLiquidity(uint160 initSqrtPriceX96) internal {
        uint256 laicyBalance = IERC20(laicyToken).balanceOf(address(this));
        require(laicyBalance > 0, "LB");
        IERC20(laicyToken).approve(nonfungiblePositionManager, laicyBalance);

        bool isLaicyToken0 = laicyToken < weth;
        int24 currentTick = TickMath.getTickAtSqrtRatio(initSqrtPriceX96);

        // Set tick range for 100% lAIcy position
        // If lAIcy is token0 (lower address), we want liquidity above current price
        // If lAIcy is token1 (higher address), we want liquidity below current price
        int24 tickLower;
        int24 tickUpper;

        if (isLaicyToken0) {
            // lAIcy is token0, so we want all lAIcy tokens
            // Price moves up when lAIcy becomes more expensive relative to WETH
            // Set range from current tick to maximum to hold all lAIcy
            tickLower = currentTick;
            tickUpper = TickMath.MAX_TICK;
        } else {
            // lAIcy is token1, so we want all lAIcy tokens
            // Price moves down when lAIcy becomes more expensive relative to WETH
            // Set range from minimum to current tick to hold all lAIcy
            tickLower = TickMath.MIN_TICK;
            tickUpper = currentTick;
        }

        INonfungiblePositionManager(nonfungiblePositionManager).mint(
            INonfungiblePositionManager.MintParams({
                token0: isLaicyToken0 ? laicyToken : weth,
                token1: isLaicyToken0 ? weth : laicyToken,
                fee: POOL_FEE,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: isLaicyToken0 ? laicyBalance : 0,
                amount1Desired: isLaicyToken0 ? 0 : laicyBalance,
                amount0Min: 0,
                amount1Min: 0,
                recipient: msg.sender,
                deadline: block.timestamp
            })
        );
    }

    function _sqrt(uint256 x) internal pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }
}
