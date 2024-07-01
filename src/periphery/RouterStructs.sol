// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

struct MintParams {
    address recipient;
    address tokenA;
    address tokenB;
    uint24 fee;
    int24 lowerTick;
    int24 upperTick;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
}

struct AddLiquidityParams {
    uint256 tokenId;
    uint256 amount0Desired;
    uint256 amount1Desired;
    uint256 amount0Min;
    uint256 amount1Min;
}

struct RemoveLiquidityParams {
    uint256 tokenId;
    uint128 liquidity;
}

struct CollectParams {
    uint256 tokenId;
    uint128 amount0;
    uint128 amount1;
}
