# 第 4 章　合约安全基础（60 分钟）

**目标**：知道最常见的几类漏洞是怎么发生的，亲眼看一次重入攻击掏空银行，然后修好它。

智能合约安全为什么格外重要：**代码即资产、部署后不可改、所有人都能调用、出了事没有回滚**。
2016 年 The DAO 被盗约 360 万 ETH，直接导致以太坊硬分叉成 ETH 和 ETC。

## 4.1 重入（Reentrancy）

### 漏洞

`src/ch04/VulnerableBank.sol`：

```solidity
function withdraw() external {
    uint256 amount = balances[msg.sender];
    require(amount > 0, "no balance");
    (bool ok,) = msg.sender.call{value: amount}("");   // ① 控制权交给对方
    require(ok, "send failed");
    balances[msg.sender] = 0;                          // ② 太晚了
}
```

`msg.sender` 如果是合约，`call` 会触发它的 `receive()`。攻击合约在 `receive()` 里再次调用 `withdraw()`，此时 ② 还没执行，余额还在：

```
attack()
 └ bank.withdraw()           余额=1，发 1 ETH
    └ attacker.receive()
       └ bank.withdraw()     余额仍=1，再发 1 ETH
          └ attacker.receive()
             └ ...           直到银行被掏空
```

`test_AttackDrainsVulnerableBank`：1 ETH 本金拿走了银行里另外 10 ETH。用 `-vvvv` 运行，看看那一层层嵌套的调用栈。

### 两道防线

**① Checks-Effects-Interactions (CEI)**：先检查条件，再修改自身状态，最后与外部交互。

**② 重入锁**。真实代码：OpenZeppelin `ReentrancyGuard`（简化）：

```solidity
uint256 private constant NOT_ENTERED = 1;
uint256 private constant ENTERED = 2;
uint256 private _status = NOT_ENTERED;   // 用 1/2 而不是 0/1：非零→非零的写入更便宜

modifier nonReentrant() {
    if (_status == ENTERED) revert ReentrancyGuardReentrantCall();
    _status = ENTERED;
    _;
    _status = NOT_ENTERED;
}
```

Uniswap V2 Pair 的 `lock` 修饰器是同一个思路（第 5 章会看到）。新版 OZ 还提供 `ReentrancyGuardTransient`，用 EIP-1153 瞬时存储，更省 gas。

### 变种

- **跨函数重入**：在 `receive()` 里调用的是同一合约的**另一个函数**（例如 `transfer`），它读到了尚未更新的状态。
- **只读重入**：攻击者在回调中调用别的协议，那个协议读取了你合约**状态更新到一半**时的 `view` 函数（如 LP 价格）。2022–2023 年多起 Curve 相关事故属于此类。
- **ERC-777 / ERC-721 回调**：`tokensReceived`、`onERC721Received` 同样会把控制权交出去。

## 4.2 访问控制

最常见、损失最大的一类问题：**忘了加权限，或权限判断写错**。

```solidity
function setOracle(address o) external { oracle = o; }            // ❌ 谁都能改预言机
function setOracle(address o) external onlyOwner { oracle = o; }  // ✅
```

真实案例：
- **Parity 多签（2017）**：钱包库合约的初始化函数没有保护，有人调用它成了 owner，然后 `selfdestruct`，冻结了约 51 万 ETH。
- **可升级合约**：实现合约的 `initialize()` 没有被调用或没加 `initializer` 修饰器，被任何人抢先初始化。

工具：OZ `Ownable`（单一 owner）、`Ownable2Step`（两步转移防手误）、`AccessControl`（基于角色）。生产中 owner 通常是多签（Safe）+ 时间锁（Timelock）。

### tx.origin 钓鱼

`test/ch04/TxOrigin.t.sol`：钱包用 `tx.origin == owner` 鉴权，主人被诱导调用钓鱼合约的 `claimAirdrop()`，钓鱼合约转手调用钱包，此时 `tx.origin` 仍是主人，鉴权通过，钱被转走。**鉴权一律用 `msg.sender`。**

## 4.3 其他高频问题（了解即可）

| 类别 | 说明 | 防范 |
|---|---|---|
| 预言机操纵 | 用 AMM 的**即时**价格当预言机，攻击者用闪电贷砸盘后借贷（第 5、6 章） | Chainlink、TWAP、多源校验 |
| 精度 / 舍入 | 先除后乘丢精度；舍入方向对协议不利；首个存款人"份额通胀攻击" | 先乘后除；对协议有利的方向舍入；锁定最小份额（Uniswap 的 MINIMUM_LIQUIDITY） |
| 抢跑 / MEV | 交易在内存池中公开，可被抢先或夹击（三明治） | 滑点保护 `amountOutMin`、deadline、私有交易池 |
| 未检查返回值 | 低层 `call` 或不标准代币的返回值没检查 | 检查 `ok`；用 SafeERC20 |
| 签名重放 | 签名缺 nonce / chainId | EIP-712 + nonce（第 3 章 Permit） |
| DoS | 遍历无界数组；依赖对方收款成功才能继续 | 分页；pull 而不是 push 付款 |
| 整数溢出 | 0.8 之前的头号问题；现在要警惕 `unchecked` 和类型强转（`uint128(x)`） | 用 OZ `SafeCast` |

## 4.4 动手（25 分钟）

1. 运行并读懂演示：
   ```bash
   forge test --match-test test_AttackDrainsVulnerableBank -vvvv
   ```
2. 实现 `src/ch04/SafeBank.sol` 的 `withdraw()`：**同时**使用 CEI 和 `nonReentrant`。
3. ```bash
   forge test --match-path "test/ch04/*" -vv
   ```
4. 进阶实验：只用 CEI、不加 `nonReentrant`，测试还能过吗？只加 `nonReentrant`、不改顺序呢？想想为什么两者都加才是好习惯。

## 小测验

1. 用一句话描述重入攻击的根本原因。
2. CEI 三个字母分别代表什么？把 `VulnerableBank.withdraw` 改成 CEI 顺序。
3. 为什么 OZ 的 `ReentrancyGuard` 用 1 和 2 而不用 0 和 1 表示状态？
4. 只读重入为什么连 `view` 函数都会出问题？
5. 为什么不能用 `tx.origin` 做权限检查？
6. 某协议直接读 Uniswap 交易对的 `getReserves()` 计算抵押品价格，有什么风险？
7. 在 `test_AttackFailsOnSafeBank` 中，攻击交易为什么会以 `SendFailed` 而不是 `ReentrancyGuardReentrantCall` revert？

<details>
<summary>答案</summary>

1. 合约在更新自身状态之前把控制权交给了外部合约（外部调用），对方在回调中利用了尚未更新的状态。
2. Checks（检查）、Effects（修改状态）、Interactions（外部交互）。先读余额并检查 > 0，再 `balances[msg.sender] = 0`，最后 `call` 转账并检查结果。
3. storage 槽从 0 写成非 0 要 20,000+ gas，非 0 改写非 0 只要约 2,900。用 1/2 让每次加锁、解锁都是"非零改非零"，更便宜。
4. 攻击者在回调中调用**第三方协议**，第三方读取了你合约的 view 函数，而此时你的状态只更新了一半（如余额已变、总量未变），算出的价格是错的。你的 `nonReentrant` 只保护会修改状态的函数，挡不住别人读 view。
5. `tx.origin` 是交易发起人，经过任何中间合约都不变。用户只要被诱导调用一个恶意合约，恶意合约就能以用户身份通过检查。
6. 储备可以在同一笔交易里被闪电贷大幅改变，攻击者先砸价/拉价，再按错误价格借贷或清算，最后还原。应该用 Chainlink 或 TWAP。
7. 重入的那次 `withdraw` 确实以 `ReentrancyGuardReentrantCall` revert，但它发生在攻击合约的 `receive()` 内部，导致外层 `call` 返回 `ok = false`，外层 `withdraw` 于是 revert `SendFailed()`。最终冒泡出来的是最外层的错误。

</details>
