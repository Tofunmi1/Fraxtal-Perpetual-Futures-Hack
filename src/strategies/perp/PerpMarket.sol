///// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SignedDecimalMath} from "./utils/SignedDecimalMath.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {PerpRouter} from "./PerpRouter.sol";

struct balance {
    int128 weight;
    int128 reducedNotional;
}

contract PerpMarket is Ownable {
    using SignedDecimalMath for int256;

    mapping(address => balance) balanceMap;
    int256 fundingRate;

    // ========== events ==========

    event BalanceChange(address indexed trader, int256 weightChange, int256 notionalChange);

    event UpdateFundingRate(int256 oldFundingRate, int256 newFundingRate);

    // ========== constructor ==========

    constructor(address _owner) Ownable(_owner) {}

    function balanceOf(address trader) external view returns (int256 weight, int256 notional) {
        weight = int256(balanceMap[trader].weight);
        notional = weight.decimalMul(fundingRate) + int256(balanceMap[trader].reducedNotional);
    }

    /// add onlyOwner modifier
    function updateFundingRate(int256 newFundingRate) external {
        int256 oldFundingRate = fundingRate;
        fundingRate = newFundingRate;
        emit UpdateFundingRate(oldFundingRate, newFundingRate);
    }

    function getFundingRate() external view returns (int256) {
        return fundingRate;
    }

    // ========== trade ==========

    function trade(bytes calldata tradeData) external {
        (address[] memory traderList, int256[] memory weightChangeList, int256[] memory notionalChangeList) =
            PerpRouter(owner()).approveTrade(msg.sender, tradeData);

        for (uint256 i = 0; i < traderList.length;) {
            _settle(traderList[i], weightChangeList[i], notionalChangeList[i]);
            unchecked {
                ++i;
            }
        }
    }

    function liquidate(address liquidator, address liquidatedTrader, int256 requestPaper, int256 expectCredit)
        external
        returns (int256 liqtorPaperChange, int256 liqtorCreditChange)
    {
        int256 liqedPaperChange;
        int256 liqedCreditChange;

        if (liqtorPaperChange < 0) {
            require(
                liqtorCreditChange * requestPaper <= expectCredit * liqtorPaperChange, "LIQUIDATION_PRICE_PROTECTION"
            );
        } else {
            require(
                liqtorCreditChange * requestPaper >= expectCredit * liqtorPaperChange, "LIQUIDATION_PRICE_PROTECTION"
            );
        }

        _settle(liquidatedTrader, liqedPaperChange, liqedCreditChange);
        _settle(liquidator, liqtorPaperChange, liqtorCreditChange);
        if (balanceMap[liquidatedTrader].weight == 0) {
            // PerpRouter(owner()).handleBadDebt(liquidatedTrader);
        }
    }

    function _settle(address trader, int256 weightChange, int256 notionalChange) internal {
        bool isNewPosition = balanceMap[trader].weight == 0;
        int256 rate = fundingRate; // gas saving
        int256 notional = int256(balanceMap[trader].weight).decimalMul(rate)
            + int256(balanceMap[trader].reducedNotional) + notionalChange;
        int128 newPaper = balanceMap[trader].weight + SafeCast.toInt128(weightChange);
        int128 newReducedCredit = SafeCast.toInt128(notional - int256(newPaper).decimalMul(rate));
        balanceMap[trader].weight = newPaper;
        balanceMap[trader].reducedNotional = newReducedCredit;
        emit BalanceChange(trader, weightChange, notionalChange);
        if (isNewPosition) {
            PerpRouter(owner()).openPosition(trader);
        }
        if (newPaper == 0) {
            // realize PNL
            // PerpRouter(owner()).realizePnl(trader, balanceMap[trader].reducedNotional);
            balanceMap[trader].reducedNotional = 0;
        }
    }
}
