//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract vFrax is ERC20 {
    constructor() ERC20("vFax", "vFrax secondary perpetual asset") {}
}
