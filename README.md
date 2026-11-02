# 区块链 + Solidity 8 小时入门（Foundry 实战版）

写给**有编程基础的 CS 毕业生**：不讲"什么是变量"，直接讲 EVM 怎么工作、Solidity 有哪些坑、主流协议的真实代码长什么样。

每章 = **讲义**（`docs/`）+ **练习合约**（`src/`，带 `TODO`）+ **Foundry 测试**（`test/`）+ **小测验**（讲义末尾）。
填完 TODO、测试全绿，这一章就算过关。

## 课程大纲

| 章 | 主题 | 真实协议代码 | 时间 | 测试 |
|---|---|---|---|---|
| [0](docs/00-setup.md) | 环境与 Foundry 速览 | — | 20 min | `test/ch00` |
| [1](docs/01-blockchain-evm.md) | 区块链与 EVM 心智模型 | Uniswap V2 `pairFor` (CREATE2) | 60 min | `test/ch01` |
| [2](docs/02-solidity-core.md) | Solidity 核心语法 | WETH9 | 75 min | `test/ch02` |
| [3](docs/03-erc20-openzeppelin.md) | ERC-20 与 OpenZeppelin | OZ v5 ERC20 / Permit / SafeERC20、USDT | 60 min | `test/ch03` |
| [4](docs/04-security.md) | 合约安全基础 | The DAO、OZ ReentrancyGuard | 60 min | `test/ch04` |
| [5](docs/05-uniswap-v2.md) | AMM：Uniswap V2 | UniswapV2Pair / UniswapV2Library | 75 min | `test/ch05` |
| [6](docs/06-lending.md) | 借贷：Compound / Aave | JumpRateModel、accrueInterest、健康因子、清算 | 75 min | `test/ch06` |
| [7](docs/07-deploy-fork.md) | 部署脚本与主网分叉测试 | 主网 Uniswap V2、Aave V3 | 35 min | `test/ch07` |
| | **合计** | | **≈ 7 h 40 min**（余 20 min 机动） | 77 个测试 |

建议节奏：两个半天。上午 0–3 章（语言 + 代币），下午 4–7 章（安全 + DeFi）。

## 快速开始

```bash
# 1. 安装 Foundry（https://book.getfoundry.sh/getting-started/installation）
curl -L https://foundry.paradigm.xyz | bash && foundryup

# 2. 进入本目录，安装依赖（forge-std 与 OpenZeppelin v5.1）
./setup.sh

# 3. 跑某一章的测试
forge test --match-path "test/ch00/*" -vv
```

## 目录结构

```
docs/        每章讲义 + 小测验（答案折叠在末尾）
src/         练习代码 —— 你要改的地方，搜索 "TODO"
solutions/   参考答案（结构与 src/ 完全相同）
test/        Foundry 测试，通过 `ex/` 前缀导入练习代码
script/      部署脚本（第 7 章）
```

测试里写的是 `import {WETH} from "ex/ch02/WETH.sol";`。`ex/` 在 `foundry.toml` 里映射到 `src/`；
切换到 `solutions` profile 时映射到 `solutions/`，所以**同一套测试**可以检验你的代码和参考答案：

```bash
forge test                              # 测你的代码（src/）
FOUNDRY_PROFILE=solutions forge test    # 测参考答案（solutions/），应当全部通过
```

## 常用命令

| 命令 | 作用 |
|---|---|
| `forge build` | 编译 |
| `forge test --match-path "test/ch03/*"` | 只跑第 3 章 |
| `forge test --match-test test_Swap -vvvv` | 只跑一个测试，并打印完整调用栈（调试神器） |
| `forge test --gas-report` | 每个函数的 gas 消耗 |
| `forge inspect WETH storageLayout` | 查看存储布局 |
| `cast sig "transfer(address,uint256)"` | 算函数选择器 |
| `anvil` | 启动本地链 |

## 学习方法

1. 先读讲义（每章 15–25 分钟），重点看"真实代码"小节；
2. 打开 `src/chXX/`，搜索 `TODO`，按 `HINT` 实现；
3. `forge test --match-path "test/chXX/*" -vv`，红了就加 `-vvvv` 看调用栈；
4. 做讲义末尾小测验，再对照答案；
5. 卡住超过 10 分钟就看 `solutions/`，不丢人。

测试里的"演示"类用例（如重入攻击、tx.origin 钓鱼）不需要你写代码，它们一开始就是绿的，目的是让你**读懂并亲手改改看**。

> 说明：第 7 章的部署脚本依赖第 3 章的 `CourseToken.mint`，分叉测试依赖第 5 章的 `getAmountOut`，所以先完成前面的章节。
