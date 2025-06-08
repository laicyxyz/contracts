// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "lib/forge-std/src/Test.sol";
import {Laicy} from "../src/Laicy.sol";

contract LaicyTest is Test {
    Laicy public laicy;
    address public deployer;

    function setUp() public {
        deployer = address(this);
        laicy = new Laicy();
    }

    function testTokenDetails() public view {
        assertEq(laicy.name(), "Laicy");
        assertEq(laicy.symbol(), "LAI");
        assertEq(laicy.decimals(), 18);

        // Check that 100 million tokens were minted to the deployer
        uint256 expectedSupply = 100_000_000 * 10 ** 18;
        assertEq(laicy.totalSupply(), expectedSupply);
        assertEq(laicy.balanceOf(deployer), expectedSupply);
    }

    function testTransfer() public {
        address user1 = address(0x1);
        address user2 = address(0x2);
        uint256 amount = 1000 * 10 ** 18; // 1000 tokens

        // Transfer tokens from deployer to user1
        laicy.transfer(user1, amount);
        assertEq(laicy.balanceOf(user1), amount);

        // Transfer tokens from user1 to user2
        vm.startPrank(user1);
        laicy.transfer(user2, amount / 2);
        vm.stopPrank();

        assertEq(laicy.balanceOf(user1), amount / 2);
        assertEq(laicy.balanceOf(user2), amount / 2);
    }
}
