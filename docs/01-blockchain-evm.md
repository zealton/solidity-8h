# 第 1 章　区块链与 EVM 心智模型（60 分钟）

**目标**：用 CS 的语言理解以太坊：它是一个**全球共享、只能追加、按交易排序执行的状态机**。
学完你应该能解释：一笔交易从签名到上链发生了什么、gas 在为什么付费、合约数据存在哪、地址是怎么算出来的。

## 1.1 一句话模型

```
世界状态 σ  ──(交易 T₁, T₂, …, Tₙ 打包成区块 B)──▶  新世界状态 σ'
```

- **状态**：一个巨大的映射 `地址 → 账户`。
- **交易**：由私钥签名的消息，唯一能改变状态的东西。
- **区块**：一批有序交易 + 指向父区块的哈希。哈希链让历史不可篡改。
- **共识**（以太坊为 PoS）：验证者质押 ETH，轮流提议区块、互相投票；作恶会被罚没。对合约开发者来说，只需记住：**交易顺序由出块者决定**（这就是 MEV/抢跑的来源，第 5 章会遇到）。
- **确定性**：每个节点独立重放所有交易，必须得到相同结果。所以合约里**没有真随机数、不能发 HTTP 请求、不能读系统时间**（只能读 `block.timestamp`）。

## 1.2 两种账户

| | EOA（外部账户） | 合约账户 |
|---|---|---|
| 控制者 | 私钥 | 代码 |
| 有代码 | 否 | 是（部署后不可改） |
| 能主动发起交易 | 能 | 不能，只能被调用 |
| 字段 | nonce, balance | nonce, balance, **code**, **storage** |

地址来源：
- EOA：`keccak256(公钥)` 的后 20 字节。
- 合约（`CREATE`）：`keccak256(rlp(部署者, 部署者nonce))` 的后 20 字节 —— 取决于 nonce，所以不好预测。
- 合约（`CREATE2`）：`keccak256(0xff ++ 部署者 ++ salt ++ keccak256(initCode))` 的后 20 字节 —— **只取决于输入，可以提前算出来**。

> **真实代码：Uniswap V2 的 `pairFor`**（v2-periphery/UniswapV2Library.sol）
> Router 要和某个交易对交互时，不去查 Factory 的 mapping（要一次外部调用，贵），而是直接算出地址：
> ```solidity
> pair = address(uint(keccak256(abi.encodePacked(
>         hex'ff',
>         factory,
>         keccak256(abi.encodePacked(token0, token1)),  // salt
>         hex'96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f' // init code hash
>     ))));
> ```
> 你在练习里要实现的就是这个公式。

## 1.3 交易与 gas

一笔交易的主要字段：`from`（由签名恢复）、`to`、`value`（附带的 ETH）、`data`（calldata）、`nonce`、`gas limit`、`maxFeePerGas` / `maxPriorityFeePerGas`。

**gas = 计算资源的计价单位**。每个 EVM 指令都有固定 gas 成本，用来防止死循环和资源滥用：

```
交易费 = gasUsed × (baseFee + priorityFee)
         baseFee 会被销毁，priorityFee 给出块者（EIP-1559）
```

几个必须有直觉的数字：

| 操作 | gas（约） |
|---|---|
| 一笔最简单的 ETH 转账 | 21,000 |
| `SSTORE` 0 → 非 0（新写一个存储槽） | 22,100（含冷访问） |
| `SSTORE` 非 0 → 非 0 | 2,900 ~ 5,000 |
| `SLOAD` 冷 / 热 | 2,100 / 100 |
| 加法、比较等算术 | 3 |

结论：**存储是最贵的资源**，Solidity 优化几乎都围绕"少读写存储"展开。

交易**失败（revert）时状态全部回滚，但已消耗的 gas 不退**。

## 1.4 EVM：一台栈式虚拟机

合约执行时能用的数据区：

| 区域 | 生命周期 | 成本 | Solidity 里对应 |
|---|---|---|---|
| stack | 指令级 | 极低 | 局部值类型变量（最多 16 个能直接访问 → "Stack too deep"） |
| memory | 单次调用 | 低，线性增长 | `memory` 变量 |
| calldata | 单次调用，只读 | 最低 | `calldata` 参数 |
| **storage** | **永久** | **高** | 状态变量 |
| transient storage | 单笔交易 | 低（EIP-1153） | `transient` 变量（0.8.28+） |

**storage 布局**：每个合约有 2²⁵⁶ 个 32 字节的槽。状态变量按声明顺序从 slot 0 开始排，小类型会打包进同一个槽。
`mapping(K => V)` 声明在 slot `p` 时，`m[k]` 存放在 `keccak256(abi.encode(k, p))`。

注意：**`private` 只是不生成 getter，链上数据对任何人都可见**（测试 `test_MappingSlot` 用 `vm.load` 直接读出来了）。

## 1.5 合约调用与 ABI

调用合约本质上是发送 calldata：

```
calldata = 函数选择器(4 字节) ++ ABI 编码的参数
选择器   = bytes4(keccak256("transfer(address,uint256)")) = 0xa9059cbb
```

所以函数签名里**不能有空格、参数名，`uint` 要写成 `uint256`**。

两个"调用者"：
- `msg.sender`：**直接**调用我的人（EOA 或合约）。
- `tx.origin`：签名这笔交易的 EOA，一路上不变。**永远不要用它做权限判断**（第 4 章演示钓鱼攻击）。

## 1.6 动手（25 分钟）

打开 `src/ch01/EVMBasics.sol`，实现 3 个函数：`selector`、`mappingSlot`、`create2Address`。

```bash
forge test --match-path "test/ch01/*" -vv
```

然后阅读 `test/ch01/EVMBasics.t.sol` 中的演示测试：
- `test_SstoreGasCost`：观察首次写入和改写的 gas 差。改成写 3 次看看。
- `test_CreateAddressDependsOnNonce`：理解为什么 CREATE 地址取决于 nonce。
- `test_MsgSenderVsTxOrigin`：理解两种调用者。

命令行练习：
```bash
cast sig "transfer(address,uint256)"        # 0xa9059cbb
cast keccak "hello"
forge inspect Layout storageLayout          # 看 Layout 合约的存储布局
```

## 小测验

1. 为什么智能合约里不能直接调用外部 HTTP API 拿 ETH 价格？DeFi 是怎么解决的？
2. 一笔交易 revert 了，用户付的 gas 费会退回吗？状态会怎样？
3. `CREATE` 和 `CREATE2` 地址的计算差别是什么？Uniswap V2 为什么用 `CREATE2` 部署交易对？
4. 合约里 `uint256 private secret = 42;`，别人能读到吗？怎么读？
5. 同样把一个值写入存储，为什么第一次写比第二次写贵得多？
6. `transfer(address, uint256)` 和 `transfer(address,uint256)` 算出的选择器一样吗？
7. A（EOA）调用合约 B，B 再调用合约 C。在 C 里 `msg.sender` 和 `tx.origin` 分别是谁？

<details>
<summary>答案</summary>

1. 每个节点都要重放交易并得到相同结果，HTTP 结果不确定。解决方案是**预言机**（如 Chainlink）：链下节点把数据写进链上合约，其他合约去读；或者使用链上 TWAP（第 5 章）。
2. 不退（已消耗的 gas 照付），所有状态修改回滚，就像没发生过一样（nonce 仍会 +1）。
3. CREATE 依赖部署者 nonce；CREATE2 依赖 salt 和 initCode 哈希，与 nonce 无关、可预测。Uniswap 用 `(token0, token1)` 做 salt，任何人都能离线算出交易对地址，Router 省去查询 Factory 的外部调用。
4. 能。`private` 只是不生成 getter。用 `cast storage <地址> <槽号>`，或测试里 `vm.load`，或直接查 RPC `eth_getStorageAt`。
5. 0 → 非 0 要在状态树里新建条目（20,000 gas + 冷访问 2,100）；改写已有值只要 2,900 左右，同一交易内再次访问是"热"的更便宜。
6. 不一样。规范签名不能有空格，带空格算出来是另一个选择器。
7. `msg.sender` = B，`tx.origin` = A。

</details>
