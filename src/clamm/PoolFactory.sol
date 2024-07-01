//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

//or deploy new pools with create2
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

// remove abstract
// plan a pool creation system basically :- router system , etc
contract Factory is Ownable {
    constructor(address admin) Ownable(admin) {}

    function deployNewPool() external {}

    function whiteListRouter() external {}
}
