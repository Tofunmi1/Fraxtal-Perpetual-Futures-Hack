//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PerpBaseTest} from "test/Perp.base.t.sol";
import {InsuranceFund} from "./../../src/strategies/perp/InsuranceFund.sol";
import {vFrax} from "./../../src/strategies/perp/collateral/vFrax.sol";
import {PerpRouter} from "./../../src/strategies/perp/PerpRouter.sol";
import {FundingRate} from "./../../src/strategies/perp/FundingRate.sol";
import {PerpMarket} from "./../../src/strategies/perp/PerpMarket.sol";
import {IERC20} from "./../../lib/forge-std/src/interfaces/IERC20.sol";

contract FundingRateTests is PerpBaseTest {
    function setUp() public override {
        super.setUp();
        address[] memory markets = new address[](3);
        int128[] memory rates = new int128[](3);
        (markets[0], markets[1], markets[2]) = (address(BTC_FRAX), address(ETH_FRAX), address(SOL_FRAX));
        fundingRate = new FundingRate(address(perpRouter), 3);
        perpRouter.updateFundingRate(markets, rates);
    }
    /*
       Test cases list
       - work when rate = 0
       - work when rate > 0
       - work when rate < 0
       - rate increase
       - rate decrease
       */

    /// todo or write some fuzz test before hackathon ends
    function test_zero_funding_rate() external {}
    function test_positive_funding_rate() external {}
    function test_negative_funding_rate() external {}
    function test_funding_rate_increase() external {}
    function test_funding_rate_decrease() external {}
}
