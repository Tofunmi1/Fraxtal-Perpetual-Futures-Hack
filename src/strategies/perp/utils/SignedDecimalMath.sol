//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

library SignedDecimalMath {
    int256 constant SignedONE = 10 ** 18;

    function decimalMul(int256 a, int256 b) internal pure returns (int256) {
        return (a * b) / SignedONE;
    }

    function decimalDiv(int256 a, int256 b) internal pure returns (int256) {
        return (a * SignedONE) / b;
    }

    function abs(int256 a) internal pure returns (uint256) {
        return a < 0 ? uint256(a * -1) : uint256(a);
    }
}
