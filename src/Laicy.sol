// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title lAIcy
 * @dev The last web3 bot you'll ever need
 * `* @dev Supporting interfaces: API, Telegram, SMS, Dapp, and much more to come
 * @dev https://laicy.xyz
 */
contract Laicy is ERC20 {
    constructor() ERC20("lAIcy", "lAIcy") {
        _mint(msg.sender, 1_000_000_000 ether);
    }
}
