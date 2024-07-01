//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "lib/forge-std/src/Test.sol";
import {PerpRouter, Order, MatchResult, MarketParams} from "src/strategies/perp/PerpRouter.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {InsuranceFund} from "src/strategies/perp/InsuranceFund.sol";
import {vFrax} from "src/strategies/perp/collateral/vFrax.sol";
import {PerpRouter} from "src/strategies/perp/PerpRouter.sol";
import {FundingRate} from "src/strategies/perp/FundingRate.sol";
import {PerpMarket} from "src/strategies/perp/PerpMarket.sol";
import {Auth} from "./../src/strategies/perp/Auth.sol";
//wrapped eth

interface WfrxETH {
    function deposit() external;
    function approve(address _to, uint256 _am) external;
}

//stable frax
interface Frax is IERC20 {
    function minter_mint(address m_address, uint256 m_amount) external;
    function addMinter(address minter_address) external;
}

///perp base test
contract PerpBaseTest is Test {
    PerpRouter internal perpRouter;
    string internal constant url = "https://rpc.frax.com"; // frax rpc

    ///addresses for fork tests (precompiles basically)
    address internal constant wfraxETH = 0xFC00000000000000000000000000000000000006;
    address internal constant frax = 0xFc00000000000000000000000000000000000001;
    address internal constant sfrxETH = 0xFC00000000000000000000000000000000000005;
    address internal constant fxs = 0xFc00000000000000000000000000000000000002;
    address internal constant fpis = 0xfc00000000000000000000000000000000000004;
    address internal constant fpi = 0xFc00000000000000000000000000000000000003;
    address internal constant sfrax = 0xfc00000000000000000000000000000000000008;

    //user addresses , lps and traders
    address internal user01 = makeAddr("user01");
    address internal user02 = makeAddr("user02");
    address internal user03 = makeAddr("user02");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    InsuranceFund internal insuranceFund;
    address internal owner = makeAddr("owner");
    vFrax internal vfrax;
    FundingRate internal fundingRate;

    PerpMarket internal BTC_FRAX;
    PerpMarket internal ETH_FRAX;
    PerpMarket internal SOL_FRAX;
    Auth internal auth;

    function setUp() public virtual {
        //anvil --fork-url https://rpc.frax.com --port 8888
        uint256 forkId = vm.createFork("http://127.0.0.1:8888", 5373320);
        vm.selectFork(forkId);
        vm.prank(address(0xC4EB45d80DC1F079045E75D5d55de8eD1c1090E6));
        Frax(frax).addMinter(address(this));
        __mintFrax(address(this), 100_000 * 1e18);
        deal(address(this), 100_000 ether);
        (bool _x,) = address(wfraxETH).call{value: 100_000 ether}(abi.encodeWithSignature("deposit()"));
        if (!_x) revert();
        Frax(frax).approve(address(this), type(uint128).max);
        WfrxETH(wfraxETH).approve(address(this), type(uint128).max);

        /* Note 
          5 characters: owner insurance trader1~3
          3 perp markets:
          - BTC 20x 
            3% liquidation 1% price offset 1% insurance 
          - ETH 10x 
            5% liquidation 1% price offset 1% insurance 
        //   - SOL  5x  
            10% liquidation 3% price offset 2% insurance 
          Init price
          - BTC 30000
          - ETH 2000
          - AR 10
        */
        vm.startPrank(owner);
        auth = Auth(owner);
        insuranceFund = new InsuranceFund(owner);
        BTC_FRAX = new PerpMarket(owner);
        ETH_FRAX = new PerpMarket(owner);
        SOL_FRAX = new PerpMarket(owner);
        vfrax = new vFrax();
        address[] memory markets;
        int128[] memory rates;
        // fundingRate = new FundingRate(owner, markets, rates);
        perpRouter = new PerpRouter(frax, address(owner), address(vfrax), address(auth));
        perpRouter.setMrketParams(
            address(BTC_FRAX), MarketParams(0.03 * 1e18, 0.03 * 1e18, 0.03 * 1e18, address(this), "btc", true)
        );
        perpRouter.setMrketParams(
            address(ETH_FRAX), MarketParams(0.03 * 1e18, 0.03 * 1e18, 0.03 * 1e18, address(this), "btc", true)
        );
        vm.stopPrank();
    }

    /// testUtils
    //prank governance address to mint some frax
    function __mintFrax(address _to, uint256 amount) internal {
        // deal(frax, _to, amount);
        Frax(frax).minter_mint(_to, amount);
    }

    function __dealWfrxETH(address _to, uint256 _amount) internal {
        IERC20(wfraxETH).approve(_to, _amount); //need to approve weth to use transfer
        IERC20(wfraxETH).transfer(_to, _amount);
    }
}
