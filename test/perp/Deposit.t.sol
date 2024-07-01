//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PerpBaseTest} from "test/Perp.base.t.sol";
import {InsuranceFund} from "./../../src/strategies/perp/InsuranceFund.sol";
import {vFrax} from "./../../src/strategies/perp/collateral/vFrax.sol";
import {PerpRouter} from "./../../src/strategies/perp/PerpRouter.sol";
import {FundingRate} from "./../../src/strategies/perp/FundingRate.sol";
import {PerpMarket} from "./../../src/strategies/perp/PerpMarket.sol";
import {IERC20} from "./../../lib/forge-std/src/interfaces/IERC20.sol";

contract DepositTest is PerpBaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_deposit() external {
        __mintFrax(address(user01), 10_000 * 1e18);
        vm.startPrank(user01);
        IERC20(frax).approve(address(perpRouter), type(uint128).max);
        perpRouter.deposit(10_000 * 1e18, 0);
        assertEq(perpRouter.getStableAssetWeight(user01), 10_000 * 1e18);
    }
}
