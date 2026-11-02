// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 摘自 Uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol
/// 原版是 0.6 + SafeMath，这里改成 0.8 原生算术，逻辑与 require 字符串保持一致。
library UniswapV2Library {
    /// 按当前储备比例报价（不含手续费），添加流动性时用
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        amountB = amountA * reserveB / reserveA;
    }

    /// @notice 练习 1：给定输入数量，求最多能换出多少（扣 0.3% 手续费）
    /// 推导：(x + 0.997·dx)(y - dy) = xy  =>  dy = 0.997·dx·y / (x + 0.997·dx)
    /// 为避免小数，分子分母同乘 1000
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        // ===== TODO BEGIN =====
        // HINT: amountInWithFee = amountIn * 997; numerator = amountInWithFee * reserveOut;
        // HINT: denominator = reserveIn * 1000 + amountInWithFee; amountOut = numerator / denominator;
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
        // ===== TODO END =====
    }

    /// @notice 练习 2：想换出 amountOut，至少要投入多少。注意要向上取整（+1），保证池子不吃亏
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
        // ===== TODO BEGIN =====
        // HINT: numerator = reserveIn * amountOut * 1000; denominator = (reserveOut - amountOut) * 997;
        // HINT: amountIn = numerator / denominator + 1;
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
        // ===== TODO END =====
    }
}
