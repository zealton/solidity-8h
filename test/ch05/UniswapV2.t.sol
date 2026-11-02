// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {UniswapV2Library} from "ex/ch05/UniswapV2Library.sol";
import {MiniPair, IUniswapV2Callee} from "ex/ch05/MiniPair.sol";

/// library 的 internal 函数会被内联；包一层 external 才能用 expectRevert 测 require
contract LibHarness {
    function getAmountOut(uint256 a, uint256 rIn, uint256 rOut) external pure returns (uint256) {
        return UniswapV2Library.getAmountOut(a, rIn, rOut);
    }
}

/// 闪电兑换：先从池子借出 token0，回调里"用一下"，然后连本带手续费还回去
contract FlashBorrower is IUniswapV2Callee {
    MiniPair public immutable pair;
    bool public called;

    constructor(MiniPair pair_) {
        pair = pair_;
    }

    function borrow(uint256 amount0, bool repayEnough) external {
        pair.swap(amount0, 0, address(this), abi.encode(repayEnough));
    }

    function uniswapV2Call(address, uint256 amount0, uint256, bytes calldata data) external {
        require(msg.sender == address(pair), "only pair"); // 真实项目必须校验回调来源
        called = true;
        // ……这里可以拿 amount0 去套利、清算……
        bool repayEnough = abi.decode(data, (bool));
        // 归还额 = 借款 / 0.997（向上取整），否则 k 检查失败
        uint256 repay = repayEnough ? amount0 * 1000 / 997 + 1 : amount0;
        pair.token0().transfer(address(pair), repay);
    }
}

contract UniswapV2Test is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;
    MiniPair pair;
    address lp = makeAddr("lp");
    address trader = makeAddr("trader");

    function setUp() public {
        tokenA = new MockERC20("Token A", "A", 18);
        tokenB = new MockERC20("Token B", "B", 18);
        pair = new MiniPair(IERC20(address(tokenA)), IERC20(address(tokenB)));
    }

    function _addLiquidity(address who, uint256 a, uint256 b) internal returns (uint256 liquidity) {
        tokenA.mint(who, a);
        tokenB.mint(who, b);
        vm.startPrank(who);
        tokenA.transfer(address(pair), a);
        tokenB.transfer(address(pair), b);
        liquidity = pair.mint(who);
        vm.stopPrank();
    }

    // ---------- 练习 1、2：Library ----------

    function test_GetAmountOut() public pure {
        // 池子 100 A : 200 B，投入 1 A
        uint256 out = UniswapV2Library.getAmountOut(1e18, 100e18, 200e18);
        assertEq(out, 1974316068794122597); // ≈1.974 B，而不是 2 B：手续费 + 价格冲击
    }

    function test_GetAmountIn() public pure {
        uint256 amountIn = UniswapV2Library.getAmountIn(1974316068794122597, 100e18, 200e18);
        assertEq(amountIn, 1e18);
    }

    function test_GetAmountOutRevertsOnZeroInput() public {
        LibHarness h = new LibHarness();
        vm.expectRevert(bytes("UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT"));
        h.getAmountOut(0, 1, 1);
    }

    /// 往返性质：按 getAmountIn 投入，一定能换出至少 amountOut
    function testFuzz_GetAmountInRoundTrip(uint256 amountOut, uint256 rIn, uint256 rOut) public pure {
        rIn = bound(rIn, 1e6, 1e30);
        rOut = bound(rOut, 1e6, 1e30);
        amountOut = bound(amountOut, 1, rOut - 1);
        uint256 amountIn = UniswapV2Library.getAmountIn(amountOut, rIn, rOut);
        vm.assume(amountIn < 1e40);
        assertGe(UniswapV2Library.getAmountOut(amountIn, rIn, rOut), amountOut);
    }

    // ---------- Pair：流动性 ----------

    function test_FirstMintLocksMinimumLiquidity() public {
        uint256 liq = _addLiquidity(lp, 1e18, 4e18);
        assertEq(liq, 2e18 - 1000); // sqrt(1e18 * 4e18) - 1000
        assertEq(pair.balanceOf(pair.DEAD()), 1000);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertEq(r0, 1e18);
        assertEq(r1, 4e18);
    }

    function test_BurnReturnsProRata() public {
        uint256 liq = _addLiquidity(lp, 10e18, 10e18);
        vm.startPrank(lp);
        pair.transfer(address(pair), liq / 2);
        (uint256 a0, uint256 a1) = pair.burn(lp);
        vm.stopPrank();
        assertApproxEqAbs(a0, 5e18, 1000);
        assertApproxEqAbs(a1, 5e18, 1000);
    }

    // ---------- 练习 3：swap 的 k 检查 ----------

    function test_Swap() public {
        _addLiquidity(lp, 100e18, 200e18);
        uint256 amountIn = 1e18;
        uint256 amountOut = UniswapV2Library.getAmountOut(amountIn, 100e18, 200e18);

        tokenA.mint(trader, amountIn);
        vm.startPrank(trader);
        tokenA.transfer(address(pair), amountIn); // 1. 先把输入币打进池子
        pair.swap(0, amountOut, trader, ""); // 2. 再申请换出
        vm.stopPrank();

        assertEq(tokenB.balanceOf(trader), amountOut);
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertGe(uint256(r0) * r1, 100e18 * 200e18); // k 只增不减（手续费留在池子里）
    }

    function test_SwapAskingOneWeiTooMuchReverts() public {
        _addLiquidity(lp, 100e18, 200e18);
        uint256 amountIn = 1e18;
        uint256 amountOut = UniswapV2Library.getAmountOut(amountIn, 100e18, 200e18);

        tokenA.mint(trader, amountIn);
        vm.startPrank(trader);
        tokenA.transfer(address(pair), amountIn);
        vm.expectRevert(bytes("UniswapV2: K"));
        pair.swap(0, amountOut + 1, trader, "");
        vm.stopPrank();
    }

    function test_SwapWithoutPayingReverts() public {
        _addLiquidity(lp, 100e18, 200e18);
        vm.expectRevert(bytes("UniswapV2: INSUFFICIENT_INPUT_AMOUNT"));
        pair.swap(0, 1e18, trader, "");
    }

    function testFuzz_KNeverDecreases(uint256 amountIn) public {
        _addLiquidity(lp, 100e18, 200e18);
        amountIn = bound(amountIn, 1e6, 1000e18);
        uint256 amountOut = UniswapV2Library.getAmountOut(amountIn, 100e18, 200e18);
        vm.assume(amountOut > 0);
        tokenA.mint(trader, amountIn);
        vm.startPrank(trader);
        tokenA.transfer(address(pair), amountIn);
        pair.swap(0, amountOut, trader, "");
        vm.stopPrank();
        (uint112 r0, uint112 r1,) = pair.getReserves();
        assertGe(uint256(r0) * r1, 100e18 * 200e18);
    }

    /// 价格冲击：同一个池子，交易越大，成交均价越差
    function test_PriceImpact() public pure {
        uint256 small = UniswapV2Library.getAmountOut(1e18, 1000e18, 2_000_000e6);
        uint256 large = UniswapV2Library.getAmountOut(100e18, 1000e18, 2_000_000e6);
        console.log("1 ETH   -> USDC (6 decimals):", small);
        console.log("100 ETH -> USDC per ETH     :", large / 100);
        assertLt(large / 100, small);
    }

    function test_FlashSwap() public {
        _addLiquidity(lp, 100e18, 100e18);
        FlashBorrower fb = new FlashBorrower(pair);
        tokenA.mint(address(fb), 1e18); // 给借款人一点钱付手续费
        fb.borrow(10e18, true);
        assertTrue(fb.called());
    }

    function test_FlashSwapWithoutFeeReverts() public {
        _addLiquidity(lp, 100e18, 100e18);
        FlashBorrower fb = new FlashBorrower(pair);
        tokenA.mint(address(fb), 1e18);
        vm.expectRevert(bytes("UniswapV2: K"));
        fb.borrow(10e18, false);
    }

    /// TWAP：累加器 = Σ(价格 × 持续秒数)。两次读数之差 / 时间差 = 时间加权均价
    function test_TwapAccumulator() public {
        _addLiquidity(lp, 100e18, 200e18); // 价格 token0 = 2 token1
        uint256 c0 = pair.price0CumulativeLast();
        uint256 t0 = block.timestamp;

        vm.warp(block.timestamp + 1 hours);
        pair.sync();

        uint256 avgPriceQ112 = (pair.price0CumulativeLast() - c0) / (block.timestamp - t0);
        assertEq(avgPriceQ112 >> 112, 2);
    }
}
