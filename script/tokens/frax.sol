//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract frax is ERC20 {
    constructor() ERC20("frax", "testnet frax") {}

    /// mint frax for demos and tests
    function mint(address _to, uint256 amount) external {
        _mint(_to, amount);
    }
}
