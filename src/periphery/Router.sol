//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IMintCallback} from "src/ICallbacks/IMintCallback.sol";
import {ISwapCallback} from "src/ICallbacks/ISwapCallback.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

//swap router and AMM Liquidity Router
contract Router is IMintCallback, ISwapCallback {
    using SafeERC20 for address;
    using SafeERC20 for IERC20;

    function mintCallback(uint256 amount0, uint256 amount1, bytes memory data) external {
        (address poolAddress) = abi.decode(data, (address));
        IERC20 token0;
        IERC20 token1;

        token0.safeTransferFrom(msg.sender, poolAddress, amount0);
        token1.safeTransferFrom(msg.sender, poolAddress, amount1);
    }

    function swapCallback(int256 amount0, int256 amount1, bytes memory data) external {}

    function _addLiquidity() internal {}
}
