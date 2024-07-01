//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Constants} from "src/lib/Constants.sol";
import {TickMath} from "src/lib/pool/TickMath.sol";

library SqrtMath {
    // babylonian method for sqrt (https://en.wikipedia.org/wiki/Methods_of_computing_square_roots#Babylonian_method)
    function sqrt(uint256 y) internal pure returns (uint256 z) {
        unchecked {
            if (y > 3) {
                z = y;
                uint256 x = y / 2 + 1;
                while (x < z) {
                    z = x;
                    x = (y / x + x) / 2;
                }
            } else if (y != 0) {
                z = 1;
            }
        }
    }

    function sqrtu(uint256 x) private pure returns (uint128) {
        if (x == 0) {
            return 0;
        } else {
            uint256 xx = x;
            uint256 r = 1;
            if (xx >= 0x100000000000000000000000000000000) {
                xx >>= 128;
                r <<= 64;
            }
            if (xx >= 0x10000000000000000) {
                xx >>= 64;
                r <<= 32;
            }
            if (xx >= 0x100000000) {
                xx >>= 32;
                r <<= 16;
            }
            if (xx >= 0x10000) {
                xx >>= 16;
                r <<= 8;
            }
            if (xx >= 0x100) {
                xx >>= 8;
                r <<= 4;
            }
            if (xx >= 0x10) {
                xx >>= 4;
                r <<= 2;
            }
            if (xx >= 0x4) r <<= 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            r = (r + x / r) >> 1;
            uint256 r1 = x / r;
            return uint128(r < r1 ? r : r1);
        }
    }

    function sqrt(int128 x) internal pure returns (int128) {
        if (x == 0) revert();
        return int128(sqrtu(uint256(int256(x)) << 64));
    }

    function divRound(int128 x, int128 y) internal pure returns (int128 result) {
        int128 _x = div(x, y);
        result = _x >> 64;

        if (_x % 2 ** 64 >= 0x8000000000000000) {
            result += 1;
        }
    }

    function div(int128 x, int128 y) internal pure returns (int128) {
        if (y == 0) revert();
        int256 result = (int256(x) << 64) / y;
        require(result >= -0x80000000000000000000000000000000 && result <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF4);
        return int128(result);
    }

    function sqrtP(uint256 price) internal pure returns (uint160) {
        return uint160(int160(sqrt(int128(int256(price << 64))) << (Constants.Q_96RESOLUTION - 64)));
    }

    function sqrtPi(uint256 price, uint24 tickSpacing) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(tickI(price, tickSpacing));
    }

    function sqrtPiFromTick(int24 _tick) internal pure returns (uint160) {
        return TickMath.getSqrtRatioAtTick(nearestUsableTick(_tick, 60));
    }

    function tick(uint256 price) internal pure returns (int24 _tick) {
        _tick = TickMath.getTickAtSqrtRatio(sqrtP(price));
    }

    function tickI(uint256 price, uint24 tickSpacing) internal pure returns (int24 _tick) {
        _tick = tick(price);
        _tick = nearestUsableTick(_tick, tickSpacing);
    }

    function sqrtPToNearestTick(uint160 sqrtP_, uint24 tickSpacing) internal pure returns (int24 _tick) {
        _tick = TickMath.getTickAtSqrtRatio(sqrtP_);
        _tick = nearestUsableTick(_tick, tickSpacing);
    }

    function nearestUsableTick(int24 _tick, uint24 tickSpacing) internal pure returns (int24 result) {
        result = int24(divRound(int128(_tick), int128(int24(tickSpacing)))) * int24(tickSpacing);

        if (result < TickMath.MIN_TICK) {
            result += int24(tickSpacing);
        } else if (result > TickMath.MAX_TICK) {
            result -= int24(tickSpacing);
        }
    }
}
