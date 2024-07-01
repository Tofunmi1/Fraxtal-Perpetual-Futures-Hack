//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "lib/forge-std/src/Test.sol";
import {SqrtMath} from "test/helpers/Sqrt.sol";
import {console2} from "lib/forge-std/src/console2.sol";

contract SqrtMathTests is Test {
    function testSqrtN() public {
        console2.log(SqrtMath.sqrtP(5000));
    }

    function testNearestUsableTick() public {
        assertEq(SqrtMath.nearestUsableTick(85176, 60), 85200);
        assertEq(SqrtMath.nearestUsableTick(85170, 60), 85200);
        assertEq(SqrtMath.nearestUsableTick(85169, 60), 85140);

        assertEq(SqrtMath.nearestUsableTick(85200, 60), 85200);
        assertEq(SqrtMath.nearestUsableTick(85140, 60), 85140);
    }

    function testTickI() public {
        assertEq(SqrtMath.tickI(5000, 60), 85200);
        assertEq(SqrtMath.tickI(4545, 60), 84240);
        assertEq(SqrtMath.tickI(6250, 60), 87420);
    }

    function testSqrtPi() public {
        assertEq(SqrtMath.sqrtPi(5000, 60), 5608950122784459951015918491039);
        assertEq(SqrtMath.sqrtPi(4545, 60), 5346092701810166522520541901099);
        assertEq(SqrtMath.sqrtPi(6250, 60), 6267377518277060417829549285552);
    }
}
