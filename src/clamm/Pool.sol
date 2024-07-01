//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC4626} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IMintCallback} from "src/ICallbacks/IMintCallback.sol";
import {ISwapCallback} from "src/ICallbacks/ISwapCallback.sol";
import "src/lib/pool/FixedPoint128.sol";
import "src/lib/pool/LiquidityMath.sol";
import "src/lib/pool/Math.sol";
import "src/lib/pool/Oracle.sol";
import "src/lib/pool/Position.sol";
import "src/lib/pool/SwapMath.sol";
import "src/lib/pool/Tick.sol";
import "src/lib/pool/TickBitmap.sol";
import "src/lib/pool/TickMath.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

//structs
struct PoolDeployArgs {
    address token0;
    address token1;
    uint160 initialSqrtP;
}

// First slot will contain essential data
struct PoolData {
    // Current sqrt(P)
    uint160 sqrtPriceX96;
    // Current tick
    int24 tick;
    // Most recent observation index
    uint16 observationIndex;
    // Maximum number of observations
    uint16 observationCardinality;
    // Next maximum number of observations
    uint16 observationCardinalityNext;
}

struct SwapState {
    uint256 amountSpecifiedRemaining;
    uint256 amountCalculated;
    uint160 sqrtPriceX96;
    int24 tick;
    uint256 feeGrowthGlobalX128;
    uint128 liquidity;
}

struct StepState {
    uint160 sqrtPriceStartX96;
    int24 nextTick;
    bool initialized;
    uint160 sqrtPriceNextX96;
    uint256 amountIn;
    uint256 amountOut;
    uint256 feeAmount;
}
/// Concentrated Liquidity implementation for ERC4626 Vault
/// playback tokens ?? , how can we eliminante the vtoken part ??
/// merge the liquidity of normal lps and leverge LP ??
/// add pauser, etc

contract Pool is ERC4626, Pausable {
    /// libraries
    using Position for Position.Info;
    using Position for mapping(bytes32 => Position.Info);
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);

    uint128 public liquidity; //L::the amount of Liquidity
    uint128 public pBLiquidity; //pBl / Play back liquidity

    mapping(int24 => Tick.Info) public ticks;
    mapping(int16 => uint256) public tickBitmap;
    mapping(bytes32 => Position.Info) public positions;

    using Oracle for Oracle.Observation[65535];
    using Position for Position.Info;
    using Position for mapping(bytes32 => Position.Info);
    using Tick for mapping(int24 => Tick.Info);
    using TickBitmap for mapping(int16 => uint256);

    // Pool parameters
    address public immutable factory;
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable tickSpacing;
    uint24 public immutable fee;

    uint256 public feeGrowthGlobal0X128;
    uint256 public feeGrowthGlobal1X128;

    PoolData public slot0;

    Oracle.Observation[65535] public observations;

    ///Note
    /// create the virtual tokens directly here in the constructor (use more of absract contracts)
    /// vTokens transfer would be authorized by the pool itself
    constructor(string memory _poolName, string memory _symbol, address _token0, address _token1)
        ERC4626(IERC20(address(this)))
        ERC20(_poolName, _symbol)
    {
        fee = 300;
        ///todo change hardcoded
        token0 = address(0xFC00000000000000000000000000000000000006); //wfraxETH
        token1 = address(0xFc00000000000000000000000000000000000001); //frax
        tickSpacing = 60;
    }

    function initialize(uint160 sqrtPriceX96) public {
        if (slot0.sqrtPriceX96 != 0) revert AlreadyInitialized();

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        (uint16 cardinality, uint16 cardinalityNext) = observations.initialize(_blockTimestamp());

        slot0 = PoolData({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            observationIndex: 0,
            observationCardinality: cardinality,
            observationCardinalityNext: cardinalityNext
        });
    }

    struct ModifyPositionParams {
        address owner;
        int24 lowerTick;
        int24 upperTick;
        int128 liquidityDelta;
    }

    function _modifyPosition(ModifyPositionParams memory params)
        internal
        returns (Position.Info storage position, int256 amount0, int256 amount1)
    {
        // gas optimizations
        PoolData memory slot0_ = slot0;
        uint256 feeGrowthGlobal0X128_ = feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128_ = feeGrowthGlobal1X128;

        position = positions.get(params.owner, params.lowerTick, params.upperTick);

        bool flippedLower = ticks.update(
            params.lowerTick,
            slot0_.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            false
        );
        bool flippedUpper = ticks.update(
            params.upperTick,
            slot0_.tick,
            int128(params.liquidityDelta),
            feeGrowthGlobal0X128_,
            feeGrowthGlobal1X128_,
            true
        );

        if (flippedLower) {
            tickBitmap.flipTick(params.lowerTick, int24(tickSpacing));
        }

        if (flippedUpper) {
            tickBitmap.flipTick(params.upperTick, int24(tickSpacing));
        }

        (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) = ticks.getFeeGrowthInside(
            params.lowerTick, params.upperTick, slot0_.tick, feeGrowthGlobal0X128_, feeGrowthGlobal1X128_
        );

        position.update(params.liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

        if (slot0_.tick < params.lowerTick) {
            amount0 = Math.calcAmount0Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );
        } else if (slot0_.tick < params.upperTick) {
            amount0 = Math.calcAmount0Delta(
                slot0_.sqrtPriceX96, TickMath.getSqrtRatioAtTick(params.upperTick), params.liquidityDelta
            );

            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick), slot0_.sqrtPriceX96, params.liquidityDelta
            );

            liquidity = LiquidityMath.addLiquidity(liquidity, params.liquidityDelta);
        } else {
            amount1 = Math.calcAmount1Delta(
                TickMath.getSqrtRatioAtTick(params.lowerTick),
                TickMath.getSqrtRatioAtTick(params.upperTick),
                params.liquidityDelta
            );
        }
    }

    function mint(address owner, int24 lowerTick, int24 upperTick, uint128 amount, bytes calldata data)
        external
        returns (uint256 amount0, uint256 amount1)
    {
        if (lowerTick >= upperTick || lowerTick < TickMath.MIN_TICK || upperTick > TickMath.MAX_TICK) {
            revert InvalidTickRange();
        }

        if (amount == 0) revert ZeroLiquidity();

        (, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: owner,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidityDelta: int128(amount)
            })
        );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        uint256 balance0Before;
        uint256 balance1Before;

        if (amount0 > 0) balance0Before = balance0();
        if (amount1 > 0) balance1Before = balance1();

        IMintCallback(msg.sender).mintCallback(amount0, amount1, data);

        if (amount0 > 0 && balance0Before + amount0 > balance0()) {
            revert InsufficientInputAmount();
        }

        if (amount1 > 0 && balance1Before + amount1 > balance1()) {
            revert InsufficientInputAmount();
        }

        emit Mint(msg.sender, owner, lowerTick, upperTick, amount, amount0, amount1);
    }

    function burn(int24 lowerTick, int24 upperTick, uint128 amount) public returns (uint256 amount0, uint256 amount1) {
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) = _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                lowerTick: lowerTick,
                upperTick: upperTick,
                liquidityDelta: -(int128(amount))
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            (position.tokensOwed0, position.tokensOwed1) =
                (position.tokensOwed0 + uint128(amount0), position.tokensOwed1 + uint128(amount1));
        }

        emit Burn(msg.sender, lowerTick, upperTick, amount, amount0, amount1);
    }

    function collect(
        address recipient,
        int24 lowerTick,
        int24 upperTick,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) public returns (uint128 amount0, uint128 amount1) {
        Position.Info memory position = positions.get(msg.sender, lowerTick, upperTick);

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            IERC20(token0).transfer(recipient, amount0);
        }

        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            IERC20(token1).transfer(recipient, amount1);
        }

        emit Collect(msg.sender, recipient, lowerTick, upperTick, amount0, amount1);
    }

    function swap(
        address recipient,
        bool zeroForOne,
        uint256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) public returns (int256 amount0, int256 amount1) {
        // Caching for gas saving
        PoolData memory slot0_ = slot0;
        uint128 liquidity_ = liquidity;

        if (
            zeroForOne
                ? sqrtPriceLimitX96 > slot0_.sqrtPriceX96 || sqrtPriceLimitX96 < TickMath.MIN_SQRT_RATIO
                : sqrtPriceLimitX96 < slot0_.sqrtPriceX96 || sqrtPriceLimitX96 > TickMath.MAX_SQRT_RATIO
        ) revert InvalidPriceLimit();

        SwapState memory state = SwapState({
            amountSpecifiedRemaining: amountSpecified,
            amountCalculated: 0,
            sqrtPriceX96: slot0_.sqrtPriceX96,
            tick: slot0_.tick,
            feeGrowthGlobalX128: zeroForOne ? feeGrowthGlobal0X128 : feeGrowthGlobal1X128,
            liquidity: liquidity_
        });

        while (state.amountSpecifiedRemaining > 0 && state.sqrtPriceX96 != sqrtPriceLimitX96) {
            StepState memory step;

            step.sqrtPriceStartX96 = state.sqrtPriceX96;

            (step.nextTick, step.initialized) =
                tickBitmap.nextInitializedTickWithinOneWord(state.tick, int24(tickSpacing), zeroForOne);

            step.sqrtPriceNextX96 = TickMath.getSqrtRatioAtTick(step.nextTick);

            (state.sqrtPriceX96, step.amountIn, step.amountOut, step.feeAmount) = SwapMath.computeSwapStep(
                state.sqrtPriceX96,
                (zeroForOne ? step.sqrtPriceNextX96 < sqrtPriceLimitX96 : step.sqrtPriceNextX96 > sqrtPriceLimitX96)
                    ? sqrtPriceLimitX96
                    : step.sqrtPriceNextX96,
                state.liquidity,
                state.amountSpecifiedRemaining,
                fee
            );

            state.amountSpecifiedRemaining -= step.amountIn + step.feeAmount;
            state.amountCalculated += step.amountOut;

            if (state.liquidity > 0) {
                state.feeGrowthGlobalX128 += FullMulDiv.mulDiv(step.feeAmount, FixedPoint128.Q128, state.liquidity);
            }

            if (state.sqrtPriceX96 == step.sqrtPriceNextX96) {
                if (step.initialized) {
                    int128 liquidityDelta = ticks.cross(
                        step.nextTick,
                        (zeroForOne ? state.feeGrowthGlobalX128 : feeGrowthGlobal0X128),
                        (zeroForOne ? feeGrowthGlobal1X128 : state.feeGrowthGlobalX128)
                    );

                    if (zeroForOne) liquidityDelta = -liquidityDelta;

                    state.liquidity = LiquidityMath.addLiquidity(state.liquidity, liquidityDelta);

                    if (state.liquidity == 0) revert NotEnoughLiquidity();
                }

                state.tick = zeroForOne ? step.nextTick - 1 : step.nextTick;
            } else if (state.sqrtPriceX96 != step.sqrtPriceStartX96) {
                state.tick = TickMath.getTickAtSqrtRatio(state.sqrtPriceX96);
            }
        }

        if (state.tick != slot0_.tick) {
            (uint16 observationIndex, uint16 observationCardinality) = observations.write(
                slot0_.observationIndex,
                _blockTimestamp(),
                slot0_.tick,
                slot0_.observationCardinality,
                slot0_.observationCardinalityNext
            );

            (slot0.sqrtPriceX96, slot0.tick, slot0.observationIndex, slot0.observationCardinality) =
                (state.sqrtPriceX96, state.tick, observationIndex, observationCardinality);
        } else {
            slot0.sqrtPriceX96 = state.sqrtPriceX96;
        }

        if (liquidity_ != state.liquidity) liquidity = state.liquidity;

        if (zeroForOne) {
            feeGrowthGlobal0X128 = state.feeGrowthGlobalX128;
        } else {
            feeGrowthGlobal1X128 = state.feeGrowthGlobalX128;
        }

        (amount0, amount1) = zeroForOne
            ? (int256(amountSpecified - state.amountSpecifiedRemaining), -int256(state.amountCalculated))
            : (-int256(state.amountCalculated), int256(amountSpecified - state.amountSpecifiedRemaining));

        if (zeroForOne) {
            IERC20(token1).transfer(recipient, uint256(-amount1));

            uint256 balance0Before = balance0();
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            if (balance0Before + uint256(amount0) > balance0()) {
                revert InsufficientInputAmount();
            }
        } else {
            IERC20(token0).transfer(recipient, uint256(-amount0));

            uint256 balance1Before = balance1();
            ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
            if (balance1Before + uint256(amount1) > balance1()) {
                revert InsufficientInputAmount();
            }
        }

        emit Swap(msg.sender, recipient, amount0, amount1, slot0.sqrtPriceX96, state.liquidity, slot0.tick);
    }

    function observe(uint32[] calldata secondsAgos) public view returns (int56[] memory tickCumulatives) {
        return observations.observe(
            _blockTimestamp(), secondsAgos, slot0.tick, slot0.observationIndex, slot0.observationCardinality
        );
    }

    function increaseObservationCardinalityNext(uint16 observationCardinalityNext) public {
        uint16 observationCardinalityNextOld = slot0.observationCardinalityNext;
        uint16 observationCardinalityNextNew =
            observations.grow(observationCardinalityNextOld, observationCardinalityNext);

        if (observationCardinalityNextNew != observationCardinalityNextOld) {
            slot0.observationCardinalityNext = observationCardinalityNextNew;
            emit IncreaseObservationCardinalityNext(observationCardinalityNextOld, observationCardinalityNextNew);
        }
    }

    ////////////////////////////////////////////////////////////////////////////
    //
    // INTERNAL
    //
    ////////////////////////////////////////////////////////////////////////////
    function balance0() internal view returns (uint256 balance) {
        balance = IERC20(token0).balanceOf(address(this));
    }

    function balance1() internal view returns (uint256 balance) {
        balance = IERC20(token1).balanceOf(address(this));
    }

    function _blockTimestamp() internal view returns (uint32 timestamp) {
        timestamp = uint32(block.timestamp);
    }

    error AlreadyInitialized();
    error FlashLoanNotPaid();
    error InsufficientInputAmount();
    error InvalidPriceLimit();
    error InvalidTickRange();
    error NotEnoughLiquidity();
    error ZeroLiquidity();

    event Burn(
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Collect(
        address indexed owner,
        address recipient,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint256 amount0,
        uint256 amount1
    );

    event Flash(address indexed recipient, uint256 amount0, uint256 amount1);

    event IncreaseObservationCardinalityNext(
        uint16 observationCardinalityNextOld, uint16 observationCardinalityNextNew
    );

    event Mint(
        address sender,
        address indexed owner,
        int24 indexed tickLower,
        int24 indexed tickUpper,
        uint128 amount,
        uint256 amount0,
        uint256 amount1
    );

    event Swap(
        address indexed sender,
        address indexed recipient,
        int256 amount0,
        int256 amount1,
        uint160 sqrtPriceX96,
        uint128 liquidity,
        int24 tick
    );
}
