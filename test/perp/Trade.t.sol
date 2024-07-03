//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PerpBaseTest} from "test/Perp.base.t.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {PerpRouter, Order, MatchResult, MarketParams, RatesInfo} from "src/strategies/perp/PerpRouter.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {InsuranceFund} from "src/strategies/perp/InsuranceFund.sol";
// import {vFrax} from "src/strategies/perp/collateral/vFrax.sol";
import {FundingRate} from "src/strategies/perp/FundingRate.sol";
import {PerpMarket} from "src/strategies/perp/PerpMarket.sol";
import {Auth} from "src/strategies/perp/Auth.sol";
import {EIP712} from "src/strategies/perp/utils/EIP712.sol";
import {vFrax} from "test/perp/vFrax/vFrax.sol";
import {SignedDecimalMath} from "src/strategies/perp/utils/SignedDecimalMath.sol";

//trades between makers and takers
contract TradeTest is PerpBaseTest {
    using SignedDecimalMath for int256;

    address internal _user01;
    address internal _user02;
    address internal _user03;
    uint256 internal _user01Pk; //private key for signing orders
    uint256 internal _user02Pk; //private key for signing orders
    uint256 internal _user03Pk; //private key for signing orders
    bytes32 internal domainSeparator;

    bytes32 public constant ORDER_TYPEHASH =
        keccak256("Order(address perp,address signer,int128 weightAmount,int128 notionalAmount)");

    struct BuildOrderParams {
        Order order;
        bytes32 hash;
        bytes signature;
    }

    struct OrderProps {
        int64 makerFeeRate;
        int64 takerFeeRate;
        address orderSender;
        bytes32 EIP712domain;
    }

    function setUp() public override {
        super.setUp();
        (_user01, _user01Pk) = makeAddrAndKey("user01");
        (_user02, _user02Pk) = makeAddrAndKey("user02");
        (_user03, _user03Pk) = makeAddrAndKey("user03");

        //deal some frax
        __mintFrax(_user01, 1000000 * 1e18);
        __mintFrax(_user02, 1000000 * 1e18);
        __mintFrax(_user03, 1000000 * 1e18);
        //mint vfrax
        vfrax.mint(_user01, 1000000 * 1e18);
        vfrax.mint(_user02, 1000000 * 1e18);
        vfrax.mint(_user03, 1000000 * 1e18);

        //setup trading accounts
        vm.startPrank(user01);
        IERC20(frax).approve(address(perpRouter), type(uint128).max);
        perpRouter.deposit(1000000 * 1e18, 0);
        vm.stopPrank();

        vm.startPrank(user02);
        IERC20(frax).approve(address(perpRouter), type(uint128).max);
        perpRouter.deposit(1000000 * 1e18, 0);
        vm.stopPrank();

        vm.startPrank(user03);
        IERC20(frax).approve(address(perpRouter), type(uint128).max);
        perpRouter.deposit(1000000 * 1e18, 0);
        vm.stopPrank();
        domainSeparator = EIP712.buildDomainSeparator("PermaX", "0.1", address(perpRouter));
        address[] memory perpList = new address[](3);
        int128[] memory rateList = new int128[](3);
        (perpList[0], perpList[1], perpList[2]) = (address(BTC_FRAX), address(ETH_FRAX), address(SOL_FRAX));
        (rateList[0], rateList[1], rateList[2]) = (1 * 1e18, 1 * 1e18, 1 * 1e18);
        vm.prank(owner);
        perpRouter.updateFundingRate(perpList, rateList);
    }

    ///Test & trade utils

    function _buildOrder(address perps, OrderProps memory props, uint256 signerPk, int128 weight, int128 notional)
        internal
        returns (BuildOrderParams memory _bod)
    {
        uint256 chainId;
        bytes32 info =
            keccak256(abi.encodePacked(props.makerFeeRate, props.takerFeeRate, block.timestamp, block.timestamp));

        Order memory order = Order({
            market: perps,
            signer: vm.addr(signerPk),
            weightAmount: weight,
            notionalAmount: notional,
            info: RatesInfo({
                mRate: props.makerFeeRate,
                tRate: props.takerFeeRate,
                expire: uint64(block.timestamp + 1000 seconds),
                nonce: uint64(block.timestamp)
            })
        });
        bytes32 orderHash = EIP712.hashTypedDataV4(domainSeparator, _structHash(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPk, orderHash);
        bytes memory signature = abi.encodePacked(r, s, v);
        _bod = BuildOrderParams({order: order, hash: orderHash, signature: signature});
    }

    function _getDefaultOrderProps() internal returns (OrderProps memory _op) {
        _op = OrderProps({
            makerFeeRate: 0.0001 * 1e18,
            takerFeeRate: 0.0005 * 1e18,
            orderSender: perpRouter.owner(),
            EIP712domain: domainSeparator
        });
    }

    function _structHash(Order memory order) internal pure returns (bytes32 structHash) {
        bytes32 orderTypeHash = ORDER_TYPEHASH;
        assembly {
            let start := sub(order, 32)
            let tmp := mload(start)
            mstore(start, orderTypeHash)
            structHash := keccak256(start, 192)
            mstore(start, tmp)
        }
    }

    function _encodeTradeData(Order[] memory _order, bytes[] memory signature, uint256[] memory matchAmountList)
        internal
        returns (bytes memory __encodedData)
    {
        __encodedData = abi.encode(_order, signature, matchAmountList);
    }

    //perp is perp market
    ///@dev let the taker be user01 and maker be user02 (e.g)
    function _openTrade(
        address taker,
        address maker,
        int128 takerWeight,
        uint256 price,
        address perp,
        OrderProps memory orderProps,
        uint256 _takerPk,
        uint256 _makerPk
    ) internal {
        int128 weight = takerWeight;
        int128 notional = weight * int128(-1); //opposite side of trade

        BuildOrderParams memory bop1 = _buildOrder(perp, orderProps, _takerPk, int128(notional), int128(weight));
        BuildOrderParams memory bop2 =
            _buildOrder(perp, orderProps, _makerPk, int128(notional * -1), int128(weight * -1));

        Order[] memory __orders = new Order[](2);
        __orders[0] = bop1.order;
        __orders[1] = bop2.order;
        bytes[] memory __sigs = new bytes[](2);
        __sigs[0] = bop1.signature;
        __sigs[1] = bop2.signature;
        uint256[] memory __amounts = new uint256[](2);
        __amounts[0] = int256(takerWeight).abs();
        __amounts[1] = int256(takerWeight).abs();
        bytes memory encodedData = _encodeTradeData(__orders, __sigs, __amounts);
        /// now trade (!)
        PerpMarket(perp).trade(encodedData);
    }

    function _checkBalance(address perp, address trader, int128 weight, int128 notional) internal {
        (int256 _weight, int256 _notional) = PerpMarket(perp).balanceOf(trader);
        assertEq(weight, _weight);
        assertEq(notional, _notional);
    }

    /*
    Test cases list
    - single match 
    - taker long
    - taker short
    - close position
    - multi match
    - maker de-duplicate
    - order with different maker fee rate
    - using maker price
    - without maker de-duplicate
    - negative fee rate
    - change funding rate

    Revert cases list
    - order price negative
    - order amount 0
    - wrong signature
    - wrong sender
    - wrong perp
    - wrong match amount
    - price not match
    - order over filled
    - be liquidated
    */

    ///@dev taker longs
    function test_match_single_order_taker_long() external {
        _openTrade(_user01, _user02, -1, 30_000, address(BTC_FRAX), _getDefaultOrderProps(), _user01Pk, _user02Pk);
        // _checkBalance(address(BTC_FRAX), user01, 1, -30_015);
        // _checkBalance(address(BTC_FRAX), user02, -1, 29_997);
    }
}
