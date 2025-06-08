// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "lib/forge-std/src/Test.sol";
import {LaicyDeployer} from "../src/LaicyDeployer.sol";
import {Laicy} from "../src/Laicy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title MockWETH9
 * @dev Mock WETH9 contract for testing
 */
contract MockWETH9 is IERC20 {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 value) external returns (bool) {
        balanceOf[msg.sender] -= value;
        balanceOf[to] += value;
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= value;
        }
        balanceOf[from] -= value;
        balanceOf[to] += value;
        emit Transfer(from, to, value);
        return true;
    }

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 value) external {
        balanceOf[msg.sender] -= value;
        totalSupply -= value;
        payable(msg.sender).transfer(value);
        emit Transfer(msg.sender, address(0), value);
    }
}

/**
 * @title MockUniswapV3Factory
 * @dev Mock Uniswap V3 Factory contract for testing
 */
contract MockUniswapV3Factory {
    mapping(address => mapping(address => mapping(uint24 => address))) public getPool;

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        require(tokenA != tokenB, "UniswapV3Factory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV3Factory: ZERO_ADDRESS");
        require(getPool[token0][token1][fee] == address(0), "UniswapV3Factory: POOL_EXISTS");

        pool = address(new MockUniswapV3Pool());
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool; // populate mapping in the reverse direction

        return pool;
    }
}

/**
 * @title MockUniswapV3Pool
 * @dev Mock Uniswap V3 Pool contract for testing
 */
contract MockUniswapV3Pool {
    uint160 public sqrtPriceX96;
    bool public initialized;

    function initialize(uint160 _sqrtPriceX96) external {
        require(!initialized, "UniswapV3Pool: ALREADY_INITIALIZED");
        sqrtPriceX96 = _sqrtPriceX96;
        initialized = true;
    }
}

/**
 * @title MockNonfungiblePositionManager
 * @dev Mock Nonfungible Position Manager contract for testing
 */
contract MockNonfungiblePositionManager {
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

    uint256 public tokenIdCounter;

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = ++tokenIdCounter;
        liquidity = 1000000;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;

        // Transfer tokens from sender to this contract
        IERC20(params.token0).transferFrom(msg.sender, address(this), amount0);
        IERC20(params.token1).transferFrom(msg.sender, address(this), amount1);

        return (tokenId, liquidity, amount0, amount1);
    }
}

/**
 * @title LaicyDeployerTest
 * @dev Test contract for LaicyDeployer
 */
contract LaicyDeployerTest is Test {
    LaicyDeployer public deployer;
    MockWETH9 public weth;
    MockUniswapV3Factory public factory;
    MockNonfungiblePositionManager public positionManager;

    function setUp() public {
        // Deploy mock contracts
        weth = new MockWETH9();
        factory = new MockUniswapV3Factory();
        positionManager = new MockNonfungiblePositionManager();

        // Fund the test contract with WETH
        vm.deal(address(this), 100 ether);
        weth.deposit{value: 100 ether}();

        // Create a new address that will deploy the LaicyDeployer
        address deployerAddress = makeAddr("deployer");
        vm.startPrank(deployerAddress);

        // Transfer WETH to the deployer address
        weth.transfer(deployerAddress, 10 ether);

        // Deploy LaicyDeployer with enough WETH
        vm.deal(deployerAddress, 1 ether); // Give some ETH for gas
        deployer = new LaicyDeployer(address(weth), address(factory), address(positionManager));

        vm.stopPrank();
    }

    function testDeployment() public view {
        // Check that Laicy token was deployed
        address laicyToken = deployer.laicyToken();
        assertTrue(laicyToken != address(0), "Laicy token not deployed");

        // Check that Uniswap V3 pool was created
        address pool = deployer.uniswapV3Pool();
        assertTrue(pool != address(0), "Uniswap V3 pool not created");

        // Check that pool was initialized with correct price
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);
        assertTrue(mockPool.initialized(), "Pool not initialized");
    }
}
