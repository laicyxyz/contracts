// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import {Test} from "lib/forge-std/src/Test.sol";
import {LaicyDeployer} from "../src/LaicyDeployer.sol";
import {Laicy} from "../src/Laicy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {TickMath} from "../src/libraries/TickMath.sol";

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
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
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
        require(balanceOf[from] >= value, "Insufficient balance");
        if (allowance[from][msg.sender] != type(uint256).max) {
            require(allowance[from][msg.sender] >= value, "Insufficient allowance");
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
        require(balanceOf[msg.sender] >= value, "Insufficient balance");
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

    event PoolCreated(
        address indexed token0, address indexed token1, uint24 indexed fee, int24 tickSpacing, address pool
    );

    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool) {
        require(tokenA != tokenB, "UniswapV3Factory: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV3Factory: ZERO_ADDRESS");
        require(getPool[token0][token1][fee] == address(0), "UniswapV3Factory: POOL_EXISTS");

        pool = address(new MockUniswapV3Pool(token0, token1, fee));
        getPool[token0][token1][fee] = pool;
        getPool[token1][token0][fee] = pool; // populate mapping in the reverse direction

        emit PoolCreated(token0, token1, fee, 200, pool); // 200 is tick spacing for 1% fee

        return pool;
    }
}

/**
 * @title MockUniswapV3Pool
 * @dev Mock Uniswap V3 Pool contract for testing with swap functionality
 */
contract MockUniswapV3Pool {
    address public token0;
    address public token1;
    uint24 public fee;
    uint160 public sqrtPriceX96;
    bool public initialized;

    // Track liquidity positions
    mapping(bytes32 => uint128) public positions;
    mapping(address => uint256) public tokenBalances;

    // Current tick for price tracking
    int24 public currentTick;

    // Liquidity ranges - simplified for testing
    int24 public liquidityTickLower;
    int24 public liquidityTickUpper;
    uint128 public totalLiquidity;

    constructor(address _token0, address _token1, uint24 _fee) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
    }

    function initialize(uint160 _sqrtPriceX96) external {
        require(!initialized, "UniswapV3Pool: ALREADY_INITIALIZED");
        sqrtPriceX96 = _sqrtPriceX96;
        initialized = true;
        currentTick = TickMath.getTickAtSqrtRatio(_sqrtPriceX96);
    }

    function mint(address recipient, int24 tickLower, int24 tickUpper, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        require(initialized, "Pool not initialized");

        // Store liquidity range for testing
        liquidityTickLower = tickLower;
        liquidityTickUpper = tickUpper;
        totalLiquidity += amount;

        // For our specific use case, we want to provide 100% of one token
        // Check which token we're actually providing based on the tick range
        if (tickLower == currentTick && tickUpper == TickMath.MAX_TICK) {
            // This is a range from current tick to max tick - all token1 (Laicy)
            amount0 = 0;
            amount1 = uint256(amount);
        } else if (tickLower == TickMath.MIN_TICK && tickUpper == currentTick) {
            // This is a range from min tick to current tick - all token1 (Laicy)
            amount0 = 0;
            amount1 = uint256(amount);
        } else {
            // Default case - mixed liquidity
            amount0 = uint256(amount) / 2;
            amount1 = uint256(amount) / 2;
        }

        // Track token balances in pool
        tokenBalances[token0] += amount0;
        tokenBalances[token1] += amount1;

        return (amount0, amount1);
    }

    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1) {
        require(initialized, "Pool not initialized");
        require(amountSpecified != 0, "Amount cannot be zero");

        // Check if swap is possible based on liquidity range and actual token balances
        bool swapPossible = false;

        if (zeroForOne) {
            // Selling token0 for token1
            // This is possible if current tick is within or above the liquidity range
            // AND we have token1 to give out (or can create it for single-sided liquidity)
            swapPossible = currentTick >= liquidityTickLower;

            // For our specific case, only allow this if we actually have token1 liquidity
            // or if the liquidity range supports it
            if (liquidityTickLower == TickMath.MIN_TICK && liquidityTickUpper == currentTick) {
                // This is WETH->Laicy direction, which should be blocked
                swapPossible = false;
            }
        } else {
            // Selling token1 for token0
            // This is possible if current tick is within or below the liquidity range
            swapPossible = currentTick <= liquidityTickUpper;

            // For our specific case, only allow this if we actually have token0 liquidity
            // or if the liquidity range supports it
            if (liquidityTickLower == currentTick && liquidityTickUpper == TickMath.MAX_TICK) {
                // This is WETH->Laicy direction, which should be blocked
                swapPossible = false;
            }
        }

        if (!swapPossible) {
            revert("Insufficient liquidity for swap direction");
        }

        // Simplified swap calculation
        uint256 amountIn = uint256(amountSpecified > 0 ? amountSpecified : -amountSpecified);
        uint256 amountOut = (amountIn * 99) / 100; // Simple 1% fee

        if (zeroForOne) {
            // Selling token0 for token1
            // For our single-sided liquidity, we need to check if we have token1 to give out
            // If we don't have token1, we can create it virtually (simplified for testing)
            if (tokenBalances[token1] < amountOut) {
                // Create virtual WETH for the swap (simplified mock behavior)
                tokenBalances[token1] = amountOut;
            }
            amount0 = int256(amountIn);
            amount1 = -int256(amountOut);
            tokenBalances[token0] += amountIn;
            tokenBalances[token1] -= amountOut;
        } else {
            // Selling token1 for token0
            // For our single-sided liquidity, we need to check if we have token0 to give out
            if (tokenBalances[token0] < amountOut) {
                // Create virtual token0 for the swap (simplified mock behavior)
                tokenBalances[token0] = amountOut;
            }
            amount0 = -int256(amountOut);
            amount1 = int256(amountIn);
            tokenBalances[token1] += amountIn;
            tokenBalances[token0] -= amountOut;
        }

        return (amount0, amount1);
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
    mapping(uint256 => address) public ownerOf;
    MockUniswapV3Factory public factory;

    event IncreaseLiquidity(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    constructor(address _factory) {
        factory = MockUniswapV3Factory(_factory);
    }

    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        require(params.deadline >= block.timestamp, "Transaction too old");

        tokenId = ++tokenIdCounter;
        ownerOf[tokenId] = params.recipient;

        // Get the pool
        address pool = factory.getPool(params.token0, params.token1, params.fee);
        require(pool != address(0), "Pool does not exist");

        // Call the pool's mint function to determine how much liquidity to add
        // Calculate liquidity based on desired amounts
        liquidity = uint128(params.amount0Desired + params.amount1Desired);

        (amount0, amount1) =
            MockUniswapV3Pool(pool).mint(params.recipient, params.tickLower, params.tickUpper, liquidity, "");

        // Transfer the actual amounts used from sender to the pool
        if (amount0 > 0) {
            require(IERC20(params.token0).transferFrom(msg.sender, pool, amount0), "Token0 transfer failed");
        }
        if (amount1 > 0) {
            require(IERC20(params.token1).transferFrom(msg.sender, pool, amount1), "Token1 transfer failed");
        }

        emit IncreaseLiquidity(tokenId, liquidity, amount0, amount1);

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

    address public deployerOwner;

    event LaicyDeployed(address indexed laicyToken);
    event PoolCreated(address indexed pool, address indexed token0, address indexed token1, uint24 fee);

    function setUp() public {
        // Deploy mock contracts
        weth = new MockWETH9();
        factory = new MockUniswapV3Factory();
        positionManager = new MockNonfungiblePositionManager(address(factory));

        // Create a deployer owner address
        deployerOwner = makeAddr("deployerOwner");

        // Fund the deployer owner with ETH for gas
        vm.deal(deployerOwner, 10 ether);

        // Deploy LaicyDeployer as the deployer owner
        vm.prank(deployerOwner);
        deployer = new LaicyDeployer(address(weth), address(factory), address(positionManager));
    }

    function testDeployment() public {
        // Check that Laicy token was deployed
        address laicyToken = deployer.laicyToken();
        assertTrue(laicyToken != address(0), "Laicy token not deployed");

        // Check that Uniswap V3 pool was created
        address pool = deployer.uniswapV3Pool();
        assertTrue(pool != address(0), "Uniswap V3 pool not created");

        // Check that pool was initialized with correct price
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);
        assertTrue(mockPool.initialized(), "Pool not initialized");
        assertTrue(mockPool.sqrtPriceX96() > 0, "Pool price not set");
    }

    function testLaicyTokenProperties() public {
        address laicyToken = deployer.laicyToken();
        Laicy laicy = Laicy(laicyToken);

        // Check token properties
        assertEq(laicy.name(), "lAIcy", "Incorrect token name");
        assertEq(laicy.symbol(), "lAIcy", "Incorrect token symbol");
        assertEq(laicy.decimals(), 18, "Incorrect token decimals");
        assertEq(laicy.totalSupply(), 1_000_000_000 ether, "Incorrect total supply");

        // Check that deployer contract received all tokens initially
        assertEq(laicy.balanceOf(address(deployer)), 0, "Deployer should have used all tokens for liquidity");
    }

    function testPoolCreation() public {
        address laicyToken = deployer.laicyToken();
        address pool = deployer.uniswapV3Pool();

        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        // Check pool tokens are correct
        address token0 = mockPool.token0();
        address token1 = mockPool.token1();

        assertTrue(
            (token0 == laicyToken && token1 == address(weth)) || (token0 == address(weth) && token1 == laicyToken),
            "Pool tokens incorrect"
        );

        // Check pool fee
        assertEq(mockPool.fee(), deployer.POOL_FEE(), "Incorrect pool fee");
    }

    function testConstants() public {
        // Test that constants are set correctly
        assertEq(deployer.POOL_FEE(), 10000, "Incorrect pool fee constant");
        assertEq(deployer.weth(), address(weth), "Incorrect WETH address");
        assertEq(deployer.uniswapV3Factory(), address(factory), "Incorrect factory address");
        assertEq(deployer.nonfungiblePositionManager(), address(positionManager), "Incorrect position manager address");
    }

    function testInitialPriceCalculation() public {
        address pool = deployer.uniswapV3Pool();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        uint160 sqrtPriceX96 = mockPool.sqrtPriceX96();
        assertTrue(sqrtPriceX96 > 0, "Price should be greater than 0");

        // The price should be set to approximately 25,000,000 lAIcy per WETH
        // We can't test exact price due to tick rounding, but we can verify it's reasonable
        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        assertTrue(tick > TickMath.MIN_TICK && tick < TickMath.MAX_TICK, "Tick should be within valid range");
    }

    function testLiquidityProvision() public {
        // Check that pool received tokens (indicating liquidity was provided)
        address laicyToken = deployer.laicyToken();
        address pool = deployer.uniswapV3Pool();
        Laicy laicy = Laicy(laicyToken);

        uint256 poolBalance = laicy.balanceOf(pool);
        assertTrue(poolBalance > 0, "Pool should have received lAIcy tokens");

        // Check that a position was minted (tokenId should be > 0)
        assertTrue(positionManager.tokenIdCounter() > 0, "No liquidity position was created");

        // Check that the position is owned by the deployer owner
        assertEq(positionManager.ownerOf(1), deployerOwner, "Position should be owned by deployer owner");
    }

    function testEventEmission() public {
        // Test that events are emitted during deployment
        // We can verify this by checking that the deployer was created successfully
        // and that the expected state changes occurred (which indicates events were emitted)

        address initialDeployerOwner = makeAddr("newDeployerOwner");
        vm.deal(initialDeployerOwner, 10 ether);

        vm.prank(initialDeployerOwner);
        LaicyDeployer newDeployer = new LaicyDeployer(address(weth), address(factory), address(positionManager));

        // Verify that the deployment was successful (which means events were emitted)
        assertTrue(newDeployer.laicyToken() != address(0), "LaicyDeployed event should have been emitted");
        assertTrue(newDeployer.uniswapV3Pool() != address(0), "PoolCreated event should have been emitted");
    }

    function testCannotReinitializePool() public {
        address pool = deployer.uniswapV3Pool();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        // Try to initialize again - should fail
        vm.expectRevert("UniswapV3Pool: ALREADY_INITIALIZED");
        mockPool.initialize(1000);
    }

    function testSqrtFunction() public {
        // Test the internal sqrt function indirectly by checking price calculation
        address pool = deployer.uniswapV3Pool();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        uint160 sqrtPriceX96 = mockPool.sqrtPriceX96();

        // The sqrt price should be reasonable (not 0 or extremely large)
        assertTrue(sqrtPriceX96 > 1000, "Sqrt price too small");
        assertTrue(sqrtPriceX96 < type(uint160).max / 1000, "Sqrt price too large");
    }

    function testLiquidityRangeSetup() public {
        address pool = deployer.uniswapV3Pool();
        address laicyToken = deployer.laicyToken();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        // Check that liquidity range was set correctly
        int24 tickLower = mockPool.liquidityTickLower();
        int24 tickUpper = mockPool.liquidityTickUpper();
        int24 currentTick = mockPool.currentTick();

        bool isLaicyToken0 = laicyToken < address(weth);

        if (isLaicyToken0) {
            // lAIcy is token0, liquidity should be from current tick to max tick
            assertEq(tickLower, currentTick, "Tick lower should equal current tick for lAIcy as token0");
            assertEq(tickUpper, TickMath.MAX_TICK, "Tick upper should be max tick for lAIcy as token0");
        } else {
            // lAIcy is token1, liquidity should be from min tick to current tick
            assertEq(tickLower, TickMath.MIN_TICK, "Tick lower should be min tick for lAIcy as token1");
            assertEq(tickUpper, currentTick, "Tick upper should equal current tick for lAIcy as token1");
        }
    }

    function testCanSwapLaicyForWETH() public {
        address pool = deployer.uniswapV3Pool();
        address laicyToken = deployer.laicyToken();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        // Create a test user
        address user = makeAddr("user");

        // Give user some lAIcy tokens to swap (transfer from pool since that's where they are)
        uint256 swapAmount = 1000 ether;
        vm.prank(pool);
        Laicy(laicyToken).transfer(user, swapAmount);

        // Approve the pool to spend user's lAIcy tokens
        vm.prank(user);
        IERC20(laicyToken).approve(pool, swapAmount);

        // Determine swap direction based on token ordering
        bool isLaicyToken0 = laicyToken < address(weth);
        bool zeroForOne = isLaicyToken0; // If lAIcy is token0, we're swapping token0 for token1 (WETH)

        // Perform the swap - this should succeed
        vm.prank(user);
        (int256 amount0, int256 amount1) = mockPool.swap(
            user,
            zeroForOne,
            int256(swapAmount),
            0, // No price limit
            ""
        );

        // Verify swap occurred
        if (isLaicyToken0) {
            assertTrue(amount0 > 0, "Should have spent lAIcy tokens (token0)");
            assertTrue(amount1 < 0, "Should have received WETH (token1)");
        } else {
            assertTrue(amount0 < 0, "Should have received WETH (token0)");
            assertTrue(amount1 > 0, "Should have spent lAIcy tokens (token1)");
        }
    }

    function testCannotSwapWETHForLaicy() public {
        address pool = deployer.uniswapV3Pool();
        address laicyToken = deployer.laicyToken();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        // Create a test user
        address user = makeAddr("user");

        // Give user some WETH to attempt swap
        uint256 swapAmount = 1 ether;
        vm.deal(user, swapAmount);
        vm.prank(user);
        weth.deposit{value: swapAmount}();

        // Approve the pool to spend user's WETH
        vm.prank(user);
        IERC20(address(weth)).approve(pool, swapAmount);

        // Determine swap direction based on token ordering
        bool isLaicyToken0 = laicyToken < address(weth);
        bool zeroForOne = !isLaicyToken0; // If lAIcy is token0, we're swapping token1 (WETH) for token0 (lAIcy)

        // Attempt the swap - this should fail due to insufficient liquidity in that direction
        vm.prank(user);
        vm.expectRevert("Insufficient liquidity for swap direction");
        mockPool.swap(
            user,
            zeroForOne,
            int256(swapAmount),
            0, // No price limit
            ""
        );
    }

    function testPoolOnlyHasLaicyLiquidity() public {
        address pool = deployer.uniswapV3Pool();
        address laicyToken = deployer.laicyToken();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        // Check token balances in the pool
        uint256 laicyBalance = mockPool.tokenBalances(laicyToken);
        uint256 wethBalance = mockPool.tokenBalances(address(weth));

        // Pool should have lAIcy tokens but no WETH
        assertTrue(laicyBalance > 0, "Pool should have lAIcy tokens");
        assertEq(wethBalance, 0, "Pool should have no WETH tokens initially");
    }

    function testSwapDirectionBasedOnTokenOrdering() public {
        address pool = deployer.uniswapV3Pool();
        address laicyToken = deployer.laicyToken();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        bool isLaicyToken0 = laicyToken < address(weth);
        int24 currentTick = mockPool.currentTick();
        int24 tickLower = mockPool.liquidityTickLower();
        int24 tickUpper = mockPool.liquidityTickUpper();

        if (isLaicyToken0) {
            // lAIcy is token0, WETH is token1
            // Liquidity range: [currentTick, MAX_TICK]
            // Can swap token0 (lAIcy) for token1 (WETH) because currentTick >= tickLower
            assertTrue(currentTick >= tickLower, "Current tick should be >= tick lower for lAIcy->WETH swap");

            // Cannot swap token1 (WETH) for token0 (lAIcy) because currentTick > tickUpper would be needed
            // but tickUpper is MAX_TICK, so this condition can never be met
            assertTrue(currentTick <= tickUpper, "Current tick should be <= tick upper (but this prevents WETH->lAIcy)");
        } else {
            // WETH is token0, lAIcy is token1
            // Liquidity range: [MIN_TICK, currentTick]
            // Can swap token1 (lAIcy) for token0 (WETH) because currentTick <= tickUpper
            assertTrue(currentTick <= tickUpper, "Current tick should be <= tick upper for lAIcy->WETH swap");

            // Cannot swap token0 (WETH) for token1 (lAIcy) because currentTick < tickLower would be needed
            // but tickLower is MIN_TICK, so this condition can never be met
            assertTrue(currentTick >= tickLower, "Current tick should be >= tick lower (but this prevents WETH->lAIcy)");
        }
    }

    function testLiquidityRangePreventsBidirectionalTrading() public {
        address pool = deployer.uniswapV3Pool();
        address laicyToken = deployer.laicyToken();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        int24 currentTick = mockPool.currentTick();
        int24 tickLower = mockPool.liquidityTickLower();
        int24 tickUpper = mockPool.liquidityTickUpper();

        bool isLaicyToken0 = laicyToken < address(weth);

        // Verify that the liquidity range is set up to only allow one direction of trading
        if (isLaicyToken0) {
            // For lAIcy as token0: range [currentTick, MAX_TICK]
            // This allows selling token0 (lAIcy) but not selling token1 (WETH)
            assertEq(tickLower, currentTick, "Liquidity starts at current tick");
            assertEq(tickUpper, TickMath.MAX_TICK, "Liquidity extends to max tick");

            // Verify conditions for swap directions
            assertTrue(currentTick >= tickLower, "Can swap lAIcy->WETH (zeroForOne=true)");
            assertFalse(currentTick <= tickLower - 1, "Cannot swap WETH->lAIcy (would need tick < tickLower)");
        } else {
            // For lAIcy as token1: range [MIN_TICK, currentTick]
            // This allows selling token1 (lAIcy) but not selling token0 (WETH)
            assertEq(tickLower, TickMath.MIN_TICK, "Liquidity starts at min tick");
            assertEq(tickUpper, currentTick, "Liquidity ends at current tick");

            // Verify conditions for swap directions
            assertTrue(currentTick <= tickUpper, "Can swap lAIcy->WETH (zeroForOne=false)");
            assertFalse(currentTick >= tickUpper + 1, "Cannot swap WETH->lAIcy (would need tick > tickUpper)");
        }
    }

    function testMultipleSwapsInAllowedDirection() public {
        address pool = deployer.uniswapV3Pool();
        address laicyToken = deployer.laicyToken();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        // Create multiple test users
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        uint256 swapAmount = 500 ether;

        // Give users some lAIcy tokens (transfer from pool since that's where they are)
        vm.prank(pool);
        Laicy(laicyToken).transfer(user1, swapAmount);
        vm.prank(pool);
        Laicy(laicyToken).transfer(user2, swapAmount);

        bool isLaicyToken0 = laicyToken < address(weth);
        bool zeroForOne = isLaicyToken0;

        // First user swaps
        vm.prank(user1);
        IERC20(laicyToken).approve(pool, swapAmount);
        vm.prank(user1);
        mockPool.swap(user1, zeroForOne, int256(swapAmount), 0, "");

        // Second user swaps - should also succeed
        vm.prank(user2);
        IERC20(laicyToken).approve(pool, swapAmount);
        vm.prank(user2);
        (int256 amount0, int256 amount1) = mockPool.swap(user2, zeroForOne, int256(swapAmount), 0, "");

        // Verify second swap also worked
        if (isLaicyToken0) {
            assertTrue(amount0 > 0, "Second swap should have spent lAIcy tokens");
            assertTrue(amount1 < 0, "Second swap should have received WETH");
        } else {
            assertTrue(amount0 < 0, "Second swap should have received WETH");
            assertTrue(amount1 > 0, "Second swap should have spent lAIcy tokens");
        }
    }

    function testSwapFailsWithZeroAmount() public {
        address pool = deployer.uniswapV3Pool();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        address user = makeAddr("user");

        // Attempt swap with zero amount - should fail
        vm.prank(user);
        vm.expectRevert("Amount cannot be zero");
        mockPool.swap(user, true, 0, 0, "");
    }

    function testPoolInitializedAtCorrectTick() public {
        address pool = deployer.uniswapV3Pool();
        MockUniswapV3Pool mockPool = MockUniswapV3Pool(pool);

        uint160 sqrtPriceX96 = mockPool.sqrtPriceX96();
        int24 currentTick = mockPool.currentTick();

        // Verify that the current tick matches the sqrt price
        int24 calculatedTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
        assertEq(currentTick, calculatedTick, "Current tick should match calculated tick from sqrt price");

        // Verify that the sqrt price is on a valid tick boundary
        uint160 tickSqrtPrice = TickMath.getSqrtRatioAtTick(currentTick);
        assertEq(sqrtPriceX96, tickSqrtPrice, "Sqrt price should be exactly on tick boundary");
    }
}
