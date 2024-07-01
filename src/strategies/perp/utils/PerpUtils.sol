//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PerpMarket} from "./../PerpMarket.sol";
import {MarketParams} from "src/strategies/perp/PerpRouter.sol";
import {IOracle} from "./../oracle/IOracle.sol";
import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {SignedDecimalMath} from "./SignedDecimalMath.sol";

library PerpUtils {
    using SignedDecimalMath for int256;

    function getTotalExposure(
        address[] storage openPositions,
        address trader,
        mapping(address => MarketParams) storage mp
    ) public view returns (int256 netPositionValue, uint256 exposure, uint256 maintenanceMargin) {
        // sum net value and exposure among all markets
        for (uint256 i = 0; i < openPositions.length;) {
            (int256 paperAmount, int256 creditAmount) = PerpMarket(openPositions[i]).balanceOf(trader);
            MarketParams storage params = mp[openPositions[i]];
            int256 price = SafeCast.toInt256(IOracle(params.markPriceSource).getMarkPrice());

            netPositionValue += paperAmount.decimalMul(price) + creditAmount;
            uint256 exposureIncrement = paperAmount.decimalMul(price).abs();
            exposure += exposureIncrement;
            maintenanceMargin += (exposureIncrement * params.liquidationThreshold) / 10 * 1e18;

            unchecked {
                ++i;
            }
        }
    }

    function isSafe(
        address[] storage openPositions,
        address trader,
        mapping(address => MarketParams) storage mp,
        int256 stableAssetWeight,
        uint256 vfraxWeight
    ) internal view returns (bool) {
        (int256 netPositionValue,, uint256 maintenanceMargin) = getTotalExposure(openPositions, trader, mp);
        return netPositionValue + stableAssetWeight >= 0
            && netPositionValue + stableAssetWeight + SafeCast.toInt256(vfraxWeight) >= SafeCast.toInt256(maintenanceMargin);
    }
}
