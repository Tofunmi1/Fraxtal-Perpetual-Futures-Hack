//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Script} from "lib/forge-std/src/Script.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract WBTC is ERC20 {
    constructor() ERC20("Wrapped Bitcoin", "WBTC") {}
}
