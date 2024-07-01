//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

struct balance {
    int128 paper;
    int128 reducedCredit;
}

struct MarketInfo {
    uint256 liquidationThreshold;
    uint256 liquidationPriceOff;
    uint256 insuranceFeeRate;
    address markPriceSource;
    string name;
    bool isRegistered;
}

contract PerpStorage {
    mapping(address => balance) public balanceMap;
    int128 public fundingRate;
}
