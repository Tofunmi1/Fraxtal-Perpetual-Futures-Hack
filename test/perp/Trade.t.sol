//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {PerpBaseTest} from "test/Perp.base.t.sol";
import {Test} from "lib/forge-std/src/Test.sol";
import {PerpRouter, Order, MatchResult, MarketParams} from "src/strategies/perp/PerpRouter.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {InsuranceFund} from "src/strategies/perp/InsuranceFund.sol";
import {vFrax} from "src/strategies/perp/collateral/vFrax.sol";
import {FundingRate} from "src/strategies/perp/FundingRate.sol";
import {PerpMarket} from "src/strategies/perp/PerpMarket.sol";
import {Auth} from "src/strategies/perp/Auth.sol";
import {EIP712} from "src/strategies/perp/utils/EIP712.sol";

//trades between makers and takers
contract TradeTest is PerpBaseTest {
    address internal _user01;
    address internal _user02;
    uint256 internal _user01Pk; //pk for signing orders
    uint256 internal _user02Pk; //pk for signing orders
    bytes32 internal domainSeparator = EIP712.buildDomainSeparator("", "0.1", address(this));

    bytes32 public constant ORDER_TYPEHASH =
        keccak256("Order(address perp,address signer,int128 weightAmount,int128 notionalAmount,bytes32 info)");

    function setUp() public override {
        super.setUp();
        (_user01, _user01Pk) = makeAddrAndKey("user01");
        (_user02, _user02Pk) = makeAddrAndKey("user01");
    }

    function _buildOrder(address trader, Order memory order, uint256 pk)
        internal
        returns (bytes32 orderHash, bytes memory signature)
    {
        uint256 chainId;
        orderHash = EIP712.hashTypedDataV4(domainSeparator, _structHash(order));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, orderHash);
        signature = abi.encodePacked(r, s, v);
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

    function _openTrade(address taker, address maker, int128 takerWeight, uint256 price, address perp) internal pure {
        int128 weight;
        int128 notional;
        // _buildOrder(trader, order, pk);
    }
}
