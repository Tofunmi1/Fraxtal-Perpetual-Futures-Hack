//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

/// insurance fund contract
contract InsuranceFund is Ownable {
    constructor(address _owner) Ownable(_owner) {}
}
