//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PerpMarket} from "./PerpMarket.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";
import {SignedDecimalMath} from "./utils/SignedDecimalMath.sol";
import {MarketParams, PerpRouter} from "src/strategies/perp/PerpRouter.sol";
import {IOracle} from "./oracle/IOracle.sol";
import {PerpMarket} from "./PerpMarket.sol";

/// contract for managing funding rate
//use int(negative) for negative funding rates
contract FundingRate is Ownable {
    using SignedDecimalMath for int256;
    using SignedDecimalMath for int128;

    address immutable perpRouter;
    uint8 immutable scale; //multiplier
    mapping(address => uint256) public fundingRateUpdateTimestamp;

    constructor(address _perpRouter, uint8 _scale) Ownable(_perpRouter) {
        perpRouter = _perpRouter;
        scale = _scale;
    }

    function updateFundingRate(address[] calldata perpList, int128[] calldata rateList) external onlyOwner {
        for (uint256 i = 0; i < perpList.length; ++i) {
            address perp = perpList[i];
            int256 oldRate = PerpMarket(perp).getFundingRate();
            uint256 maxChange = getMaxChange(perp);
            require((rateList[i] - oldRate).abs() <= maxChange, "FUNDING_RATE_CHANGE_TOO_MUCH");
            fundingRateUpdateTimestamp[perp] = block.timestamp;
        }

        PerpRouter(perpRouter).updateFundingRate(perpList, rateList);
    }

    function getMaxChange(address perp) public view returns (uint256) {
        MarketParams memory params = PerpRouter(perpRouter).getMarketParams(perp);
        uint256 markPrice = IOracle(params.markPriceSource).getMarkPrice();
        uint256 timeInterval = block.timestamp - fundingRateUpdateTimestamp[perp];
        uint256 maxChangeRate = (scale * timeInterval * params.liquidationThreshold) / (1 days);
        uint256 maxChange = (maxChangeRate * markPrice) / 10 ** 18;
        return maxChange;
    }
}
