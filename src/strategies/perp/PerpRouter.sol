//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Auth} from "./Auth.sol";
import {PerpMarket} from "./PerpMarket.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {EIP712} from "./utils/EIP712.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {SignedDecimalMath} from "./utils/SignedDecimalMath.sol";
import {PerpUtils} from "./utils/PerpUtils.sol";
import {Ownable} from "lib/openzeppelin-contracts/contracts/access/Ownable.sol";

//structs
struct Order {
    // address of perpetual market
    address market;
    address signer;
    // positive(negative) if you want to open long(short) position
    int128 weightAmount;
    // negative(positive) if you want to open long(short) position
    int128 notionalAmount;
    RatesInfo info;
}

struct RatesInfo {
    int64 mRate;
    int64 tRate;
    uint64 expire;
    uint64 nonce;
}

struct MatchResult {
    address[] traderList;
    int256[] weightChangeList;
    int256[] notionalChangeList;
    int256 orderSenderFee;
}

struct MarketParams {
    uint256 liquidationThreshold;
    uint256 liquidationPriceOff;
    uint256 insuranceFeeRate;
    address markPriceSource;
    string name;
    bool isRegistered;
}

//Our implementation of clearing house
/// deposit, liquidate, eip712 signing for perp engine
/// gas optimizations(todo) , solve stack too deep issues (done)
/// market making by both takers and makers (done)
/// makers and taker fees (done)
///use custom errors
contract PerpRouter is Ownable {
    using SafeERC20 for IERC20;
    using SignedDecimalMath for int256;

    ///errors
    error DEPOSIT_FAILED();

    address public immutable stableAsset; //frax
    Auth immutable auth;
    address public immutable vFrax; //vfrax is our secondary asset
    mapping(address => MarketParams) public marketParameters;
    address public insuranceFund;
    address internal fundingRateKeeper;

    mapping(address => int256) internal stableAssetWeight;
    mapping(address => uint256) internal vfraxWeight;
    /// let's use a withdrawal timelock
    uint256 internal withdrawTimeLock;
    mapping(address => uint256) internal pendingPrimaryWithdraw;
    mapping(address => uint256) internal pendingSecondaryWithdraw;
    mapping(address => uint256) internal withdrawExecutionTimestamp;
    address[] internal registeredPerp;
    mapping(address => address[]) internal openPositions;
    mapping(address => mapping(address => uint256)) internal positionSerialNum;
    mapping(bytes32 => uint256) internal orderFilledWeightAmount;
    mapping(address => bool) internal validOrderSender;
    mapping(address => mapping(address => bool)) internal operatorRegistry;

    bytes32 public immutable domainSeparator;

    bytes32 public constant ORDER_TYPEHASH =
        keccak256("Order(address perp,address signer,int128 weightAmount,int128 notionalAmount)");

    error UnAuthorized(address);

    //set order sender, insurance,withdrawTimeLock and funding rate keeper
    constructor(address _stableAsset, address _owner, address _vfrax, address _auth) Ownable(_owner) {
        stableAsset = _stableAsset;
        domainSeparator = EIP712.buildDomainSeparator("PermaX", "0.1", address(this));
        vFrax = _vfrax;
        auth = Auth(_auth);
        validOrderSender[_owner] = true;
    }

    modifier Authorized() {
        // if (!auth.isAuthorziedPerp(msg.sender)) revert UnAuthorized(msg.sender);
        _;
    }

    function deposit(uint256 _amount0, uint256 _amount1) external {
        _deposit(_amount0, _amount1);
    }

    function _deposit(uint256 _amount0, uint256 _amount1) internal {
        if (_amount0 > 0) {
            IERC20(stableAsset).safeTransferFrom(msg.sender, address(this), _amount0);
            stableAssetWeight[msg.sender] += int256(_amount0);
        }
        if (_amount1 > 0) {
            IERC20(vFrax).safeTransferFrom(msg.sender, address(this), _amount1);
            vfraxWeight[msg.sender] += _amount1;
        }
    }

    //add keeper check
    function updateFundingRate(address[] calldata perpList, int128[] calldata rateList) external onlyOwner {
        for (uint256 i; i < perpList.length; ++i) {
            PerpMarket(perpList[i]).updateFundingRate(rateList[i]);
        }
    }

    /// implement withdrawal

    function openPosition(address trader) external Authorized {
        openPositions[trader].push(msg.sender);
    }

    // function handleBadDebt(address liquidatedTrader) external {
    //     if (openPositions[liquidatedTrader].length == 0) {
    //         int256 _stableAssetWeight = stableAssetWeight[liquidatedTrader];
    //         uint256 _vfraxWeight = vfraxWeight[liquidatedTrader];
    //         stableAssetWeight[address(insuranceFund)] += _stableAssetWeight;
    //         vfraxWeight[address(insuranceFund)] += _vfraxWeight;
    //         stableAssetWeight[liquidatedTrader] = 0;
    //         vfraxWeight[liquidatedTrader] = 0;
    //     }
    // }

    function approveTrade(address orderSender, bytes calldata tradeData)
        external
        returns (
            // Authorized
            address[] memory, // traderList
            int256[] memory, // weightChangeList
            int256[] memory // notionalChangeList
        )
    {
        // require(validOrderSender[orderSender], "INVALID_ORDER_SENDER");

        /*
            parse tradeData
            Pass in all orders and their signatures that need to be matched.
            Also, pass in the amount you want to fill each order.
        */
        (Order[] memory orderList, bytes[] memory signatureList, uint256[] memory matchWeightAmount) =
            abi.decode(tradeData, (Order[], bytes[], uint256[]));
        bytes32[] memory orderHashList = new bytes32[](orderList.length);

        // validate all orders
        //no need for unchecked i in new solidity 0.8.25
        for (uint256 i = 0; i < orderList.length; ++i) {
            Order memory order = orderList[i];
            bytes32 orderHash = EIP712.hashTypedDataV4(domainSeparator, _structHash(order));
            orderHashList[i] = orderHash;
            address recoverSigner = ECDSA.recover(orderHash, signatureList[i]);
            // requirements
            require(recoverSigner == order.signer, "INVALID_ORDER_SIGNATURE");
            require(order.info.expire >= block.timestamp, "ORDER_EXPIRED");
            require(
                (order.weightAmount < 0 && order.notionalAmount > 0)
                    || (order.weightAmount > 0 && order.notionalAmount < 0),
                "ORDER_PRICE_NEGATIVE"
            );
            require(order.market == msg.sender, "PERP_MISMATCH");
            require(i == 0 || order.signer != orderList[0].signer, "Errors.ORDER_SELF_MATCH");
            orderFilledWeightAmount[orderHash] += matchWeightAmount[i];
            require(
                orderFilledWeightAmount[orderHash] <= int256(orderList[i].weightAmount).abs(), "ORDER_FILLED_OVERFLOW"
            );
        }

        MatchResult memory result = _matchOrders(orderList, matchWeightAmount);

        // charge fee
        stableAssetWeight[orderSender] += result.orderSenderFee;
        // cache on stack for stack too deep error
        int256 _stAweight = stableAssetWeight[orderSender];
        uint256 _vfxWeight = vfraxWeight[orderSender];
        // if orderSender pay fees to traders, check if orderSender is safe
        // if (result.orderSenderFee < 0) {
        //     require(
        //         PerpUtils.isSafe(openPositions[orderSender], orderSender, marketParameters, _stAweight, _vfxWeight),
        //         "Errors.ORDER_SENDER_NOT_SAFE"
        //     );
        // }

        return (result.traderList, result.weightChangeList, result.notionalChangeList);
    }

    // ========== matching[important] ==========

    /// @notice calculate balance changes
    /// @dev Every matching contains 1 taker order and
    /// at least 1 maker order.
    /// orderList[0] is taker order and all others are maker orders.
    /// Maker orders should be sorted by signer addresses in ascending.
    /// So that the function could merge orders to save gas.
    function _matchOrders(Order[] memory orderList, uint256[] memory matchWeightAmount)
        internal
        pure
        returns (MatchResult memory result)
    {
        // check basic match weight amount and filter unique traders
        {
            require(orderList.length >= 2, "INVALID_TRADER_NUMBER");
            // de-duplicated maker
            uint256 uniqueTraderNum = 2;
            uint256 totalMakerFilledWeight = matchWeightAmount[1];
            // start from the second maker, which is the third trader
            for (uint256 i = 2; i < orderList.length;) {
                totalMakerFilledWeight += matchWeightAmount[i];
                if (orderList[i].signer > orderList[i - 1].signer) {
                    uniqueTraderNum = uniqueTraderNum + 1;
                } else {
                    require(orderList[i].signer == orderList[i - 1].signer, "ORDER_WRONG_SORTING");
                }
                unchecked {
                    ++i;
                }
            }
            // taker match amount must equals summary of makers' match amount
            require(matchWeightAmount[0] == totalMakerFilledWeight, "TAKER_TRADE_AMOUNT_WRONG");
            // result.traderList[0] is taker
            // result.traderList[1:] are makers
            result.traderList = new address[](uniqueTraderNum);
            result.traderList[0] = orderList[0].signer;
        }

        // calculating balance change
        result.weightChangeList = new int256[](result.traderList.length);
        result.notionalChangeList = new int256[](result.traderList.length);
        {
            // the taker's trader index is 0
            // the first maker's trader index is 1
            uint256 currentTraderIndex = 1;
            result.traderList[1] = orderList[1].signer;
            for (uint256 i = 1; i < orderList.length; i++) {
                _priceMatchCheck(orderList[0], orderList[i]);

                // new maker, currentTraderIndex +1
                if (i >= 2 && orderList[i].signer != orderList[i - 1].signer) {
                    currentTraderIndex = currentTraderIndex + 1;
                    result.traderList[currentTraderIndex] = orderList[i].signer;
                }

                // calculate matching result, use maker's price
                int256 weightChange = orderList[i].weightAmount > 0
                    ? SafeCast.toInt256(matchWeightAmount[i])
                    : -1 * SafeCast.toInt256(matchWeightAmount[i]);
                int256 notionalChange = (weightChange * orderList[i].notionalAmount) / orderList[i].weightAmount;
                int256 fee = SafeCast.toInt256(notionalChange.abs()).decimalMul(orderList[i].info.mRate);
                // serialNum is used for frontend level PNL calculation
                // store matching result, including fees
                result.weightChangeList[currentTraderIndex] += weightChange;
                result.notionalChangeList[currentTraderIndex] += notionalChange - fee;
                result.weightChangeList[0] -= weightChange;
                result.notionalChangeList[0] -= notionalChange;
                result.orderSenderFee += fee;
            }
        }

        // trading fee calculation
        //stack too deep embed
        {
            // calculate takerFee based on taker's notional matching amount
            int256 takerFee = SafeCast.toInt256(result.notionalChangeList[0].abs()).decimalMul(orderList[0].info.tRate);
            result.notionalChangeList[0] -= takerFee;
            result.orderSenderFee += takerFee;
        }
    }

    // ========== order check ==========

    function _priceMatchCheck(Order memory takerOrder, Order memory makerOrder) private pure {
        int256 temp1 = int256(makerOrder.notionalAmount) * int256(takerOrder.weightAmount);
        int256 temp2 = int256(takerOrder.notionalAmount) * int256(makerOrder.weightAmount);

        if (takerOrder.weightAmount > 0) {
            require(makerOrder.weightAmount < 0, "ORDER_PRICE_NOT_MATCH");
            require(temp1 <= temp2, "ORDER_PRICE_NOT_MATCH");
        } else {
            require(makerOrder.weightAmount > 0, "ORDER_PRICE_NOT_MATCH");
            require(temp1 >= temp2, "ORDER_PRICE_NOT_MATCH");
        }
    }

    // ========== EIP712 struct hash ==========
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

    function setMrketParams(address perp, MarketParams calldata param) external onlyOwner {
        marketParameters[perp] = param;
    }

    function getStableAssetWeight(address user) external view returns (int256) {
        return stableAssetWeight[user];
    }

    function getMarketParams(address perp) external view returns (MarketParams memory) {
        return marketParameters[perp];
    }
}
