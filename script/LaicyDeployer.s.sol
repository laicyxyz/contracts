// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {LaicyDeployer} from "../src/LaicyDeployer.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IWETH9
 * @dev Interface for WETH9
 */
interface IWETH9 is IERC20 {
    function deposit() external payable;
}

/**
 * @title LaicyDeployerScript
 * @dev A script that deploys the LaicyDeployer contract, which handles:
 * - Deploying the Laicy token
 * - Creating a Uniswap V3 pool
 * - Initializing the pool with a specific price
 * - Adding liquidity to the pool
 */
contract LaicyDeployerScript is Script {
    // Mainnet addresses
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant UNISWAP_V3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    function run() public {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy LaicyDeployer contract which will:
        // 1. Deploy the Laicy token
        // 2. Create a Uniswap V3 pool
        // 3. Initialize the pool with a specific price (25,000,000 lAIcy per WETH)
        // 4. Add liquidity to the pool
        LaicyDeployer deployer = new LaicyDeployer(WETH, UNISWAP_V3_FACTORY, NONFUNGIBLE_POSITION_MANAGER);

        // Log deployment details
        address laicyToken = deployer.laicyToken();
        address uniswapPool = deployer.uniswapV3Pool();

        console.log("LaicyDeployer deployed at:", address(deployer));
        console.log("Laicy token deployed at:", laicyToken);
        console.log("Uniswap V3 pool created at:", uniswapPool);

        // Stop broadcasting transactions
        vm.stopBroadcast();
    }
}
