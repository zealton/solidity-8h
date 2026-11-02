# 第 6 章　借贷协议：Compound 与 Aave（75 分钟）

**目标**：理解超额抵押借贷的四个核心机制：**利率模型、利息指数、健康因子、清算**，读懂 Compound V2 和 Aave V3 的对应代码，并在一个 200 行的迷你借贷协议里实现它们。

## 6.1 业务模型

```
存款人 ── 存 USDC ──▶ ┌──────────┐ ◀── 抵押 WETH ── 借款人
       ◀─ 份额(cToken/aToken) │  资金池  │ ── 借出 USDC ──▶
       ◀── 利息 ─────── └──────────┘ ◀── 还款+利息 ──
                         ▲
               清算人：借款人抵押不足时替他还债，折价拿走抵押品
```

- **超额抵押**：链上没有信用评分，借 1,500 必须先押 2,000 的资产。
- **池化**：存款人和借款人不需要一一匹配，利率由**资金利用率**算法决定。
- **无需许可的清算**：任何人都能当清算人，靠清算奖励驱动，保证坏账不累积。

## 6.2 利率模型：拐点利率（Jump Rate）

资金利用率 `U = 借款总额 / (现金 + 借款总额 - 储备金)`。

U 越高，借款越贵，从而抑制借款、吸引存款。超过拐点（kink，一般 80%~90%）后利率陡增，保证池子里永远有现金可供提取。

> **真实代码：Compound `JumpRateModelV2.sol`**
> ```solidity
> function getBorrowRateInternal(uint cash, uint borrows, uint reserves) internal view returns (uint) {
>     uint util = utilizationRate(cash, borrows, reserves);
>     if (util <= kink) {
>         return ((util * multiplierPerBlock) / BASE) + baseRatePerBlock;
>     } else {
>         uint normalRate = ((kink * multiplierPerBlock) / BASE) + baseRatePerBlock;
>         uint excessUtil = util - kink;
>         return ((excessUtil * jumpMultiplierPerBlock) / BASE) + normalRate;
>     }
> }
> function getSupplyRate(uint cash, uint borrows, uint reserves, uint reserveFactorMantissa) public view returns (uint) {
>     uint oneMinusReserveFactor = BASE - reserveFactorMantissa;
>     uint borrowRate = getBorrowRateInternal(cash, borrows, reserves);
>     uint rateToPool = borrowRate * oneMinusReserveFactor / BASE;
>     return utilizationRate(cash, borrows, reserves) * rateToPool / BASE;
> }
> ```

**存款利率 = U × 借款利率 × (1 − 储备金率)**。直觉：借款人付的利息，协议抽成后，摊给所有存款（包括没借出去的）。

Aave V3 的 `DefaultReserveInterestRateStrategy` 是同样的两段式曲线，参数叫 `baseVariableBorrowRate`、`variableRateSlope1`、`variableRateSlope2`、`optimalUsageRatio`。

## 6.3 利息指数：O(1) 给所有人计息

几万个借款人，不可能每秒遍历一遍算利息。解决方案是**全局指数**：

```
borrowIndex 从 1.0 开始，每次有人交互时：
    borrowIndex ← borrowIndex × (1 + 利率 × 经过时间)

每个借款人只记两个数：(principal, 借款时的 borrowIndex)
当前债务 = principal × 当前 borrowIndex / 借款时的 borrowIndex
```

这样每次交互只更新一个全局变量，任何时候都能 O(1) 算出任何人的债务。这个模式在 DeFi 里无处不在（Aave 的 `liquidityIndex`、Synthetix/MasterChef 的奖励分发 `rewardPerToken` 都是同一思路）。

> **真实代码：Compound `CToken.accrueInterest()`**（精简）
> ```solidity
> uint borrowRateMantissa = interestRateModel.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);
> uint blockDelta = currentBlockNumber - accrualBlockNumberPrior;
>
> Exp memory simpleInterestFactor = mul_(Exp({mantissa: borrowRateMantissa}), blockDelta);
> uint interestAccumulated = mul_ScalarTruncate(simpleInterestFactor, borrowsPrior);
> uint totalBorrowsNew = interestAccumulated + borrowsPrior;
> uint totalReservesNew = mul_ScalarTruncateAddUInt(Exp({mantissa: reserveFactorMantissa}), interestAccumulated, reservesPrior);
> uint borrowIndexNew = mul_ScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);
> ```
> ```solidity
> function borrowBalanceStoredInternal(address account) internal view returns (uint) {
>     BorrowSnapshot storage borrowSnapshot = accountBorrows[account];
>     if (borrowSnapshot.principal == 0) return 0;
>     uint principalTimesIndex = borrowSnapshot.principal * borrowIndex;
>     return principalTimesIndex / borrowSnapshot.interestIndex;
> }
> ```

每次 accrue 之间按单利，多次 accrue 之间形成复利，所以**交互越频繁越接近连续复利**（`test_InterestCompoundsWithMoreAccruals`）。

**存款人的收益**体现在份额价值上：

```
Compound: exchangeRate = (cash + totalBorrows − totalReserves) / cToken总量   // cToken 数量不变，单价上涨
Aave:     aToken 余额 = scaledBalance × liquidityIndex                        // 余额自动上涨（rebasing）
```

## 6.4 健康因子与清算

> **真实代码：Aave V3 `GenericLogic.calculateUserAccountData`**
> ```solidity
> vars.healthFactor = (vars.totalDebtInBaseCurrency == 0)
>     ? type(uint256).max
>     : (vars.totalCollateralInBaseCurrency.percentMul(vars.avgLiquidationThreshold))
>         .wadDiv(vars.totalDebtInBaseCurrency);
> ```

```
健康因子 HF = 抵押品价值 × 清算阈值 / 债务价值
HF ≥ 1 安全；HF < 1 可被清算
```

Aave 区分两个参数：
- **LTV**（以太坊主网 WETH 约 80%）：借款时最多能借到抵押品价值的多少；
- **清算阈值**（WETH 约 83%）：债务超过这个比例才会被清算。两者之间的缓冲区让用户不会一借款就被清算。

**清算流程**：
1. 价格下跌，借款人 HF < 1；
2. 清算人替借款人偿还部分债务（**close factor**，通常最多 50%；Aave V3 在 HF < 0.95 时允许清算 100%，不同版本细节有调整）；
3. 清算人获得 `偿还额 × (1 + 清算奖励)` 价值的抵押品（WETH 的奖励约 5%）；
4. 借款人债务和抵押品同时减少，HF 回升。

清算是协议的**最后一道防线**：如果价格跌得太快，抵押品价值低于债务，清算人无利可图，协议就会产生坏账。所以协议对波动大的资产设置更低的 LTV。

**预言机至关重要**：价格错了，健康的仓位会被错误清算，或者攻击者能用虚高的抵押品借空池子。Compound 和 Aave 都用 Chainlink，并有额外保护（如 Compound 的价格锚定、Aave 的 fallback oracle）。

## 6.5 动手（35 分钟）

`src/ch06/` 下：

1. `JumpRateModel.sol`：实现 `getBorrowRate` 和 `getSupplyRate`（几乎就是照抄 Compound）。
2. `MiniLending.sol`：实现 `accrueInterest()`（Compound 风格）和 `healthFactor()`（Aave 风格）。合约其余部分已写好，请通读一遍：`supply / redeem / borrow / repay / liquidate`。

参数：LTV 75%，清算阈值 80%，close factor 50%，清算奖励 5%，储备金率 10%；利率模型基础 2%、斜率 20%、拐点 80%、拐点后斜率 300%。

```bash
forge test --match-path "test/ch06/*" -vv
```

读一读 `test_LiquidationAfterPriceDrop` 里的数字，自己手算一遍：ETH 从 2000 跌到 1800，HF 为什么是 0.96？清算人赚了多少？

## 小测验

1. 资金利用率 90%，按本章参数，年化借款利率和存款利率分别是多少？
2. 为什么利率曲线要在拐点后陡增？
3. 不用利息指数，给每个借款人计息会遇到什么问题？
4. 小明在 `borrowIndex = 1.02` 时借了 1,000 USDC，现在 `borrowIndex = 1.0812`，他欠多少？
5. 抵押 10 ETH（每个 2,000 USD），借了 12,000 USDC，清算阈值 80%，ETH 跌到多少时可以被清算？
6. 为什么要有 close factor，而不是一次把整个仓位清算掉？
7. Compound 的 cToken 和 Aave 的 aToken 在"体现利息"的方式上有什么不同？
8. 如果借贷协议用某个 Uniswap 池子的即时价格作为预言机，攻击者可以怎么获利？

<details>
<summary>答案</summary>

1. 借款利率 = 2% + 80%×20% + (90%−80%)×300% = 18% + 30% = 48%；存款利率 = 90% × 48% × (1 − 10%) ≈ 38.9%。
2. 保证流动性：利用率接近 100% 时存款人提不出钱。陡增的利率会迅速吸引还款和新存款，把利用率压回拐点以下。
3. 利息随时间连续增长，要么每次都遍历所有借款人（gas 无法承受、无界循环），要么每人各自记录时间和利率（利率随利用率实时变化，算不清）。指数把"全局利率历史"压缩成一个数。
4. 1000 × 1.0812 / 1.02 = 1,060 USDC。
5. HF = 10 × P × 0.8 / 12000 < 1 ⟹ P < 1,500 USD。
6. 避免借款人因小幅跌破阈值就失去全部抵押品；部分清算通常就足以让 HF 回到 1 以上，同时降低清算对市场的冲击。
7. cToken 数量不变，`exchangeRate` 上涨，赎回时换回更多标的资产；aToken 是 rebasing 代币，余额本身随 `liquidityIndex` 增长，1 aUSDC 始终约等于 1 USDC。
8. 用闪电贷在该池子里大量买入抵押品，推高价格 → 存入抵押品，按虚高价格借出大量其他资产 → 在池子里卖回、归还闪电贷。最后留下坏账，协议亏损。（2020 年的 bZx、2022 年的多起事件都属于此类。）

</details>
