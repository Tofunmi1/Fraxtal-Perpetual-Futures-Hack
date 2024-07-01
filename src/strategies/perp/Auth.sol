//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

///Auth contract for our dex
contract Auth is Ownable {
    constructor(address _owner) Ownable(_owner) {}

    // mapping(address => bool) public isAuthorziedPerp;

    mapping(address => bool) public isAuthorziedFundingManager;

    function authorizeFundingManager(address manager) external onlyOwner {
        isAuthorziedFundingManager[manager] = true;
    }

    function isAuthorziedPerp(address) external pure returns (bool) {
        return true;
    }
}
