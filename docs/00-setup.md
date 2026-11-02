# 第 0 章　环境与 Foundry 速览（20 分钟）

**目标**：装好工具，跑通第一个测试，知道 Foundry 测试怎么写。

## 0.1 为什么选 Foundry

智能合约开发有两大工具链：Hardhat（JS/TS 写测试）和 Foundry（**用 Solidity 写测试**）。
Foundry 更快，测试与合约同语言，自带模糊测试和主网分叉，是目前新项目的主流选择（Uniswap V4、Aave V3 后续开发、Morpho 等都在用）。

Foundry 包含 4 个工具：

| 工具 | 作用 |
|---|---|
| `forge` | 编译、测试、部署 |
| `cast` | 命令行和链交互（查余额、发交易、算选择器） |
| `anvil` | 本地以太坊节点 |
| `chisel` | Solidity REPL |

## 0.2 安装

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
forge --version
cd solidity-8h && ./setup.sh
```

编辑器推荐 VS Code + "Solidity" 插件（Nomic Foundation 出品）。

## 0.3 一个 Foundry 测试长什么样

打开 `test/ch00/Counter.t.sol`：

```solidity
contract CounterTest is Test {          // 继承 forge-std 的 Test
    Counter counter;

    function setUp() public {           // 每个测试前都会重新执行
        counter = new Counter();
    }

    function test_Increment() public {  // test 开头 = 普通测试
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function testFuzz_SetNumber(uint256 x) public {  // 有参数 = 模糊测试，随机跑 256 次
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
```

你会反复用到的**作弊码**（cheatcodes，只在测试里有效）：

| 作弊码 | 作用 |
|---|---|
| `vm.prank(addr)` / `vm.startPrank(addr)` | 让下一次 / 之后所有调用的 `msg.sender` 变成 `addr` |
| `vm.deal(addr, amount)` | 直接设置 ETH 余额 |
| `deal(token, addr, amount)` | 直接设置 ERC-20 余额 |
| `vm.warp(ts)` / `vm.roll(n)` | 修改区块时间 / 区块高度 |
| `vm.expectRevert(...)` | 断言下一次调用会 revert |
| `vm.expectEmit(...)` | 断言下一次调用会发出某个事件 |
| `makeAddr("alice")` | 生成一个带标签的地址 |
| `bound(x, min, max)` | 把模糊测试的随机输入限制在区间内 |

## 0.4 动手

1. `forge test --match-path "test/ch00/*" -vv`，你会看到 `test_Decrement` 和 `test_DecrementRevertsAtZero` 失败。
2. 打开 `src/ch00/Counter.sol`，实现 `decrement()`。
3. 再跑一次，全绿。
4. 试试 `-vvvv`：故意写错一次，看看 Foundry 打印的调用栈。

## 小测验

1. `setUp()` 在什么时候执行？两个测试函数之间的状态会互相影响吗？
2. 函数名 `testFuzz_X(uint256 a)` 和 `test_X()` 在 Foundry 里有什么不同？
3. 想让下一次调用的 `msg.sender` 是 `alice`，用哪个作弊码？
4. `vm.expectRevert(Counter.Underflow.selector)` 必须写在被测调用的前面还是后面？
5. `forge test -vvvv` 比 `-vv` 多输出了什么？

<details>
<summary>答案</summary>

1. 每个测试函数执行前都会执行一次；每个测试都从 `setUp` 后的干净状态开始，互不影响。
2. 带参数的测试会被当作模糊测试，Foundry 自动生成随机输入跑多次（默认 256 次，本项目在 `foundry.toml` 里配置）。
3. `vm.prank(alice)`（只影响下一次调用）或 `vm.startPrank(alice)` … `vm.stopPrank()`。
4. 前面。`expect*` 系列都是"对下一次调用的预期"。
5. 调用栈（trace）：每次外部调用的参数、返回值、事件和 revert 原因。`-vvv` 只给失败的测试打印调用栈，`-vvvv` 给所有测试打印，并包含 setUp。

</details>
