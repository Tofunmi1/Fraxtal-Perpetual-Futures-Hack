//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

contract PerpRouterStorage {
    // primary asset, ERC20
    address primaryAsset;
    // secondary asset, ERC20
    address secondaryAsset;
    // credit, gained by deposit assets
    mapping(address => int256) primaryCredit;
    mapping(address => uint256) secondaryCredit;
    // withdrawal request time lock
    uint256 withdrawTimeLock;
    // pending primary asset withdrawal amount
    mapping(address => uint256) pendingPrimaryWithdraw;
    // pending secondary asset withdrawal amount
    mapping(address => uint256) pendingSecondaryWithdraw;
    // withdrawal request executable timestamp
    mapping(address => uint256) withdrawExecutionTimestamp;
    // perpetual contract registry, for view
    address[] registeredPerp;
    // all open positions of a trader
    mapping(address => address[]) openPositions;
    // For offchain pnl calculation, serial number +1 whenever
    // position is fully closed.
    // trader => perpetual contract address => current serial Num
    mapping(address => mapping(address => uint256)) positionSerialNum;
    // filled amount of orders
    mapping(bytes32 => uint256) orderFilledPaperAmount;
    // valid order sender registry
    mapping(address => bool) validOrderSender;
    // operator registry
    // client => operator => isValid
    mapping(address => mapping(address => bool)) operatorRegistry;
    // insurance account
    address insurance;
    // funding rate keeper, normally an EOA account
    address fundingRateKeeper;
}
