//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

// test vfrax contract multi-collateral backed token
contract vFrax is ERC20 {
    constructor() ERC20("TEST", "TEST") {}

    function mint(address _to, uint256 amount) external {
        _mint(_to, amount);
    }
}
