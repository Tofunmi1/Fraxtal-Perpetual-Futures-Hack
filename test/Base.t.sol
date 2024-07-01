//// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {Test} from "lib/forge-std/src/Test.sol";
import {Pool} from "./../src/clamm/Pool.sol";
import {Tick, LiquidityMath} from "src/lib/pool/Tick.sol";
import {TickMath} from "src/lib/pool/TickMath.sol";
import {IERC20} from "lib/forge-std/src/interfaces/IERC20.sol";
import {SqrtMath} from "test/helpers/Sqrt.sol";

//wrapped eth
interface WfrxETH {
    function deposit() external;
    function approve(address _to, uint256 _am) external;
}

//stable frax
interface Frax is IERC20 {
    function minter_mint(address m_address, uint256 m_amount) external;
    function addMinter(address minter_address) external;
}

contract Base is Test {
    Pool internal pool; //default pool
    string internal constant url = "https://rpc.frax.com"; // frax rpc

    ///addresses for fork tests (precompiles basically)
    address internal constant wfraxETH = 0xFC00000000000000000000000000000000000006;
    address internal constant frax = 0xFc00000000000000000000000000000000000001;
    address internal constant sfrxETH = 0xFC00000000000000000000000000000000000005;
    address internal constant fxs = 0xFc00000000000000000000000000000000000002;
    address internal constant fpis = 0xfc00000000000000000000000000000000000004;
    address internal constant fpi = 0xFc00000000000000000000000000000000000003;
    address internal constant sfrax = 0xfc00000000000000000000000000000000000008;

    //user addresses , lps and traders
    address internal user01 = makeAddr("user01");
    address internal user02 = makeAddr("user02");
    address internal user03 = makeAddr("user02");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public virtual {
        //anvil --fork-url https://rpc.frax.com --port 8888
        uint256 forkId = vm.createFork("http://127.0.0.1:8888", 5373320);
        vm.selectFork(forkId);
        pool = new Pool("frxWfrxETH", "frxWfrxETH", frax, wfraxETH); //default pool
        pool.initialize(1384457890978632609440879126285521);
        vm.prank(address(0xC4EB45d80DC1F079045E75D5d55de8eD1c1090E6));
        Frax(frax).addMinter(address(this));
        __mintFrax(address(this), 100_000 * 1e18);
        deal(address(this), 100_000 ether);
        (bool _x,) = address(wfraxETH).call{value: 100_000 ether}(abi.encodeWithSignature("deposit()"));
        if (!_x) revert();
        Frax(frax).approve(address(this), type(uint128).max);
        WfrxETH(wfraxETH).approve(address(this), type(uint128).max);
    }

    /// testUtils
    //prank governance address to mint some frax
    function __mintFrax(address _to, uint256 amount) internal {
        // deal(frax, _to, amount);
        Frax(frax).minter_mint(_to, amount);
    }

    function __dealWfrxETH(address _to, uint256 _amount) internal {
        IERC20(wfraxETH).approve(_to, _amount); //need to approve weth to use transfer
        IERC20(wfraxETH).transfer(_to, _amount);
    }

    function testAddLiqudityMint() public {
        // assertTrue(true);
        __mintFrax(address(user01), 10 * 1e18);
        int24 _lowerTick = 84240;
        int24 _upperTick = 86100;
        bytes memory data = abi.encode(address(pool), frax, wfraxETH);
        // vm.startPrank(user01);
        __addLiquidity(user01, address(pool), _lowerTick, _upperTick, 1 ether, 5000 * 1e18, data);
    }

    function testRemoveLiquidityBurn() public {
        __mintFrax(address(user01), 10 * 1e18);
        int24 _lowerTick = 192180;
        int24 _upperTick = 193380;
        bytes memory data = abi.encode(address(pool), frax, wfraxETH);
        // vm.startPrank(user01);
        __addLiquidity(address(this), address(pool), _lowerTick, _upperTick, 0, 100 * 1e18, data);
        pool.burn(_lowerTick, _upperTick, 1.086 * 1e17);
    }

    function testSwap() public {
        int24 _lowerTick = 192180;
        int24 _upperTick = 193380;
        bytes memory data = abi.encode(address(pool), frax, wfraxETH);
        __addLiquidity(user01, address(pool), _lowerTick, _upperTick, 0, 100 * 1e18, data);
        __dealWfrxETH(user01, 10 * 1e18);
        __mintFrax(user01, 10_000 * 1e18);
        vm.startPrank(user01);
        SwapRelayParams memory srP = SwapRelayParams(address(pool), frax, wfraxETH, 10 * 1e18, 0, true);
        __swapRelay(srP);
        pool.swap(address(this), srP.zeroForOne, srP.amountIn, srP.sPLimitX96, data);
    }

    struct LiqRange {
        uint128 amount;
        int24 lowerTick;
        int24 upperTick;
    }

    function _LPRange(uint256 lowerPrice, uint256 upperPrice, uint256 amount0, uint256 amount1, uint256 currentPrice)
        internal
        returns (LiqRange memory _lqR)
    {
        uint24 _tickDistance = pool.tickSpacing();
        _lqR = LiqRange({
            lowerTick: SqrtMath.tickI(lowerPrice, _tickDistance),
            upperTick: SqrtMath.tickI(upperPrice, _tickDistance),
            amount: LiquidityMath.getLiquidityForAmounts(
                SqrtMath.sqrtP(currentPrice),
                SqrtMath.sqrtPi(lowerPrice, _tickDistance),
                SqrtMath.sqrtPi(upperPrice, _tickDistance),
                amount0,
                amount1
            )
        });
    }

    //create positions (mostly overlapping positions for swap tests)
    function __createAndSetUpPool(uint256 currentPrice, bool mintLiquidity, LiqRange[] memory _liqRanges)
        public
        returns (uint256 balance0, uint256 balance1)
    {
        pool = new Pool("frxWfrxETH", "frxWfrxETH", frax, wfraxETH); //default pool
        // pool.initialize(1384457890978632609440879126285521);
        pool.initialize(5602277097478613991869082763264);
        bytes memory data = abi.encode(address(pool), wfraxETH, frax);
        uint256 _x;
        uint256 _y;
        if (mintLiquidity) {
            for (uint256 i; i < _liqRanges.length; i++) {
                (_x, _y) = pool.mint(
                    address(this), _liqRanges[i].lowerTick, _liqRanges[i].upperTick, _liqRanges[i].amount, data
                );
                balance0 = balance0 + _x;
                balance1 = balance1 + _y;
            }
        }
    }

    function test_swap() public {
        __mintFrax(address(user01), 10 * 1e18);
        // vm.startPrank(user01);
        //set up pool , provide liquidity in some range and swap basically
        LiqRange memory _liqRange1 = _LPRange(4545, 5500, 1 ether, 5000 ether, 5000);
        LiqRange memory _liqRange2 = _LPRange(4000, 4545, 1 ether, 5000 ether, 5000);
        LiqRange[] memory _liqRanges = new LiqRange[](2);
        _liqRanges[0] = _liqRange1;
        _liqRanges[1] = _liqRange2;
        __createAndSetUpPool(5000, true, _liqRanges);
        bytes memory data = abi.encode(address(pool), wfraxETH, frax);
        pool.slot0();
        pool.swap(address(this), true, 2 * 1e18, SqrtMath.sqrtP(4094), data);
    }

    //callbacks
    // IMintCallback(msg.sender).mintCallback(amount0, amount1, data);
    function mintCallback(uint256 amount0, uint256 amount1, bytes memory data) external {
        (address _pool, address token0, address token1) = abi.decode(data, (address, address, address));
        ///send straight callback
        IERC20(token0).approve(_pool, amount1);
        if (amount0 > 0) IERC20(token0).transfer(_pool, amount0);
        IERC20(token1).approve(_pool, amount1);
        if (amount1 > 0) IERC20(token1).transfer(_pool, amount1);
    }

    // ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);
    function swapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory data) external {
        (address _pool, address token0, address token1) = abi.decode(data, (address, address, address));
        if (amount0Delta > 0) {
            IERC20(token0).approve(_pool, uint256(amount1Delta));
            IERC20(token0).transfer(_pool, uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(token1).approve(_pool, uint256(amount1Delta));
            IERC20(token1).transfer(_pool, uint256(amount1Delta));
        }
    }
    // ISwapCallback(msg.sender).swapCallback(amount0, amount1, data);

    function swapCallback(int256 amount0Delta, int256 amount1Delta) external {
        bytes memory data;
        (address _pool,,) = abi.decode(data, (address, address, address));
        uint256 amountOut = amount0Delta > 0 ? uint256(-amount1Delta) : uint256(-amount0Delta);
        (uint160 spX96After, int24 tickAfter,,,) = pool.slot0();
        // assembly {
        //     let ptr := mload(0x40)
        //     mstore(ptr, amountOut)
        //     mstore(add(ptr, 0x20), spX96After)
        //     mstore(add(ptr, 0x40), tickAfter)
        //     revert(ptr, 0x60)
        // }
    }

    function __addLiquidity(
        address owner,
        address _pool,
        int24 lowerTick,
        int24 upperTick,
        uint256 amount0,
        uint256 amount1,
        bytes memory data
    ) internal {
        (uint160 spX96,,,,) = pool.slot0();
        uint128 liquidity = LiquidityMath.getLiquidityForAmounts(
            spX96, TickMath.getSqrtRatioAtTick(lowerTick), TickMath.getSqrtRatioAtTick(upperTick), amount0, amount1
        );
        pool.mint(owner, lowerTick, upperTick, liquidity, data);
    }

    function __swapRelay(SwapRelayParams memory sp) internal {
        bool zeroForOne = sp.tokenIn < sp.tokenOut;
        if (sp.sPLimitX96 == 0) {
            if (zeroForOne) {
                sp.sPLimitX96 = TickMath.MIN_SQRT_RATIO + 1;
            } else {
                sp.sPLimitX96 = TickMath.MAX_SQRT_RATIO - 1;
            }
        }
        sp.zeroForOne = zeroForOne;
    }

    function __removeLiqudity() internal {}
}

struct SwapRelayParams {
    address pool;
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
    uint160 sPLimitX96;
    bool zeroForOne;
}
