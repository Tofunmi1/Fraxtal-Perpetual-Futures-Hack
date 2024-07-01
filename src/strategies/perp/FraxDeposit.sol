//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {PerpMarket} from "./PerpMarket.sol";
import {PerpRouter} from "./PerpRouter.sol";

contract FraxDeposit {
    using SafeERC20 for IERC20;

    address public immutable frax;
    address public immutable perpRouter;
    uint256 internal constant minDeposit = 10 * 1e18;

    constructor(address _perpRouter, address _frax) {
        perpRouter = _perpRouter;
        frax = _frax;
    }

    function depositStableCoin(uint256 amount) external {
        IERC20(frax).safeTransferFrom(msg.sender, address(this), amount);
        require(amount >= minDeposit, "receive amount is too small");
        IERC20(frax).approve(perpRouter, amount);
        PerpRouter(perpRouter).deposit(amount, 0);
    }
}
