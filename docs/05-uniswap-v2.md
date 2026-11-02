# 第 5 章　AMM：Uniswap V2（75 分钟）

**目标**：理解恒定乘积做市商的数学，读懂 UniswapV2Pair 的 `mint / burn / swap`，亲手实现报价函数和 k 检查，并理解闪电兑换与 TWAP 预言机。

Uniswap V2（2020）只有几百行代码，却是 DeFi 的基石：SushiSwap、PancakeSwap 等几十个分叉直接沿用，V3/V4 也建立在它的思想之上。

## 5.1 恒定乘积公式

池子里有 x 个 token0、y 个 token1，规则只有一条：**交易后 x·y 不能变小**。

```
x · y = k
```

用 dx 个 token0 换 token1，忽略手续费：

```
(x + dx)(y - dy) = xy   ⟹   dy = y·dx / (x + dx)
```

加上 0.3% 手续费（只有 99.7% 的输入参与定价，手续费留在池中，所以 k 会慢慢变大，这就是 LP 的收益）：

```
dy = 0.997·dx·y / (x + 0.997·dx)
```

几个推论：
- **现货价格** = y / x。交易会推动价格，单笔越大，**价格冲击**越大（`test_PriceImpact`）。
- 池子永远不会被买空：dy 永远小于 y。
- 外部价格变化后，**套利者**会来交易，把池子价格拉回市场价。AMM 的价格靠套利维持。
- **无常损失**：价格偏离存入时越多，LP 相对"单纯持币"亏得越多。

## 5.2 真实代码：UniswapV2Library

`v2-periphery/contracts/libraries/UniswapV2Library.sol`，把公式乘以 1000 变成整数运算：

```solidity
function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) internal pure returns (uint amountOut) {
    require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
    require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');
    uint amountInWithFee = amountIn.mul(997);
    uint numerator = amountInWithFee.mul(reserveOut);
    uint denominator = reserveIn.mul(1000).add(amountInWithFee);
    amountOut = numerator / denominator;
}
```

`getAmountIn` 是反函数，结果 `+1` 向上取整：**舍入永远朝对池子有利的方向**。

## 5.3 真实代码：UniswapV2Pair

Pair 合约最重要的设计：**它不关心币是怎么进来的，只比较 `balanceOf(this)` 和记账的 `reserve`**。
所以用法总是"先把币转进来，再调用函数"，Router 负责把这两步放进同一笔交易。

### mint：添加流动性

```solidity
uint amount0 = balance0 - _reserve0;   // 新转入的数量
uint amount1 = balance1 - _reserve1;
if (_totalSupply == 0) {
    liquidity = Math.sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY;
    _mint(address(0), MINIMUM_LIQUIDITY);   // 永久锁定 1000 份
} else {
    liquidity = Math.min(amount0 * _totalSupply / _reserve0, amount1 * _totalSupply / _reserve1);
}
```

- 首次用 `sqrt(x·y)`：LP 份额与初始价格无关。
- 锁定 `MINIMUM_LIQUIDITY` 是为了防**份额通胀攻击**：否则第一个人可以只铸 1 wei 份额，然后直接转入大量代币，把每份价格抬得极高，后来者因整数除法舍入而被吞掉资金。
- 之后取 `min`：按比例多给的那一边等于白送给池子。

### swap：先转出，再检查

```solidity
function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
    ...
    if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // 乐观转出
    if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out);
    if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data); // 闪电兑换回调
    balance0 = IERC20(_token0).balanceOf(address(this));
    balance1 = IERC20(_token1).balanceOf(address(this));

    uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
    uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
    require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
    { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
    uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
    uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
    require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
    }
    _update(balance0, balance1, _reserve0, _reserve1);
}
```

最后那个 `require` 就是整个 AMM 的安全核心：**扣掉输入部分的 0.3% 之后，k 不能变小**。不管你怎么操作，只要最后这一行过了，池子就不亏。

### 闪电兑换（Flash Swap）

因为是"先转出、后检查"，你可以**不先付钱**就拿走代币，在 `uniswapV2Call` 回调里随便用（套利、清算、换抵押品），只要回调结束前把钱（加手续费）还回来。还不上？整笔交易 revert，就像什么都没发生过。
这是"闪电贷"的一种，只在区块链的原子交易里才可能实现。见 `test_FlashSwap`。

> 回调里一定要校验 `msg.sender == pair`，否则任何人都能直接调用你的 `uniswapV2Call`。

### TWAP 预言机

```solidity
// _update 中，每个区块第一次交易时
price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
```

累加器 = Σ(价格 × 持续时间)。外部合约在 t₁、t₂ 各读一次，`(c₂ - c₁) / (t₂ - t₁)` 就是这段时间的**时间加权平均价格**。
操纵 TWAP 需要在很长时间内持续维持错误价格，成本极高，比读即时 `getReserves()` 安全得多。

几个工程细节：
- `reserve0/reserve1/blockTimestampLast` 是 `uint112 + uint112 + uint32 = 256` 位，**正好打包进一个存储槽**。
- 累加器故意允许溢出（`unchecked`），因为只用差值，模运算下差值仍然正确。
- 价格用 UQ112x112 定点数（左移 112 位），因为 Solidity 没有小数。

## 5.4 动手（35 分钟）

`src/ch05/` 下有两个文件：

1. `UniswapV2Library.sol`：实现 `getAmountOut`、`getAmountIn`。
2. `MiniPair.sol`：UniswapV2Pair 的 0.8 精简版（去掉了 Factory 和协议费）。实现 `swap` 里的 **k 检查**（3 行）。

```bash
forge test --match-path "test/ch05/*" -vv
```

完成后读这几个测试并思考：
- `test_SwapAskingOneWeiTooMuchReverts`：多要 1 wei 都不行，说明 `getAmountOut` 恰好是边界。
- `test_FlashSwapWithoutFeeReverts`：只还本金为什么会失败？
- `test_TwapAccumulator`：改成先 warp 30 分钟、中间做一笔大 swap、再 warp 30 分钟，平均价格会怎样？

## 小测验

1. 池子有 100 ETH 和 200,000 USDC，忽略手续费，用 10 ETH 能换多少 USDC？实际成交均价是多少？
2. 为什么 `getAmountIn` 的结果要 +1？
3. Pair 合约为什么设计成"先转币再调用 mint/swap"，而不是在函数里 `transferFrom`？这样做对普通用户有什么要求？
4. `MINIMUM_LIQUIDITY` 解决了什么问题？
5. 闪电兑换为什么不会让池子亏钱？
6. 为什么不能直接用 `getReserves()` 计算出的即时价格做借贷协议的预言机？TWAP 为什么更安全？
7. `reserve0`、`reserve1` 为什么用 `uint112` 而不是 `uint256`？
8. 用户在 Router 上 swap 时要填 `amountOutMin`，它防的是什么？

<details>
<summary>答案</summary>

1. dy = 200000 × 10 / (100 + 10) ≈ 18,181.8 USDC，均价约 1,818 USDC/ETH，远低于现货价 2,000，这就是价格冲击。
2. 整数除法向下取整，算出的输入可能差一点不够，导致 k 检查失败。+1 保证向上取整，宁可用户多付 1 wei，也不让池子吃亏。
3. 这样 Pair 不依赖 approve，也能兼容各种奇怪的代币，逻辑只看余额差，更简单、更安全。代价是普通用户不能直接用 Pair（先转币的那笔交易会被别人抢走收益），必须通过 Router 在同一笔交易里完成两步。
4. 防止首个 LP 通过"铸 1 wei 份额 + 直接捐赠大量代币"把单份价格抬得极高，使后续 LP 因舍入损失资金。锁定 1000 份让这种攻击成本极高。
5. 回调结束后，`swap` 末尾的 k 检查照常执行，借出的钱没有连本带手续费还回来就 revert，整笔交易回滚。
6. 即时储备可以在同一笔交易里被闪电贷任意操纵（操纵后借贷，再换回去）。TWAP 是一段时间的平均值，要操纵就得在多个区块里持续维持错误价格，同时会被套利者吃掉，成本极高。
7. 两个 uint112 加一个 uint32 时间戳正好 256 位，三者打包进一个存储槽，每次 `_update` 只需写一个槽，省下大量 gas。uint112 的最大值约 5×10³³，足够大。
8. 防滑点和三明治攻击：如果交易执行前价格被别人推高（或抢跑），实际换得的数量低于 `amountOutMin`，交易 revert。

</details>
