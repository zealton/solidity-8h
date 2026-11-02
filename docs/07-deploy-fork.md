# 第 7 章　部署脚本与主网分叉测试（35 分钟）

**目标**：用 Foundry 脚本把合约部署到本地链，用 `cast` 和它交互；在**主网分叉**上直接调用真实的 Uniswap 和 Aave，验证你在第 5 章写的代码和主网一致。

## 7.1 本地链 + 部署脚本

`script/DeployCourseToken.s.sol`：

```solidity
contract DeployCourseToken is Script {
    function run() external returns (CourseToken token) {
        uint256 pk = vm.envOr("PRIVATE_KEY", ANVIL_KEY_0);
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk);              // 之后的调用都会变成真实交易
        token = new CourseToken(deployer);
        token.mint(deployer, 1_000e18);
        vm.stopBroadcast();
    }
}
```

```bash
# 终端 1：启动本地链（自带 10 个各有 10000 ETH 的测试账户）
anvil

# 终端 2：部署
forge script script/DeployCourseToken.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# 用 cast 交互（把 <TOKEN> 换成上一步打印的地址）
cast call <TOKEN> "totalSupply()(uint256)" --rpc-url http://127.0.0.1:8545
cast call <TOKEN> "balanceOf(address)(uint256)" 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 --rpc-url http://127.0.0.1:8545
cast send <TOKEN> "transfer(address,uint256)" 0x70997970C51812dc3A010C7d01b50e0d17dc79C8 1e18 \
    --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 --rpc-url http://127.0.0.1:8545
```

要点：
- 不加 `--broadcast` 只做模拟。部署记录保存在 `broadcast/` 目录。
- 部署到测试网（如 Sepolia）只需换 `--rpc-url`，并通过环境变量提供私钥；加 `--verify` 可以在 Etherscan 上验证源码。
- **私钥永远不要写进代码或提交到 git**。生产环境用硬件钱包（`--ledger`）或 `cast wallet import` 加密的 keystore（`--account`）。
- 脚本也是代码，也要测试：`test/ch07/DeployScript.t.sol`。

## 7.2 主网分叉测试

`vm.createSelectFork(rpcUrl)` 会在本地按需拉取主网状态，之后的一切调用都在本地执行，不花真钱，并且可以随意使用作弊码（`deal` 改余额、`prank` 冒充任何地址）。

这是 DeFi 开发中最常用的测试方式：和真实协议集成、复现线上事故、写攻击 PoC。

```bash
export MAINNET_RPC_URL=https://eth-mainnet.g.alchemy.com/v2/<你的 key>   # 或任意主网 RPC
forge test --match-path test/ch07/MainnetFork.t.sol -vv
```

`test/ch07/MainnetFork.t.sol` 包含三个测试（未设置 `MAINNET_RPC_URL` 时自动跳过）：

| 测试 | 内容 |
|---|---|
| `test_OurLibraryMatchesMainnetRouter` | 读主网 USDC/WETH 交易对的储备，用**你写的** `getAmountOut` 报价，与主网 Router 的 `getAmountsOut` 逐 wei 比对 |
| `test_SwapOnMainnetFork` | 用 1 ETH 在真实的 Uniswap V2 上换 USDC |
| `test_AaveV3SupplyAndBorrow` | 在真实的 Aave V3 上存 10 WETH、借 5000 USDC，打印健康因子 |

技巧：
- `vm.createSelectFork(rpc, 19_000_000)` 固定区块号，结果可复现，并且 Foundry 会缓存状态，第二次运行快得多。
- `cast run <txhash> --rpc-url $MAINNET_RPC_URL` 可以在本地重放并打印任意一笔主网交易的完整调用栈，分析攻击事件时非常有用。

## 7.3 动手

1. 启动 anvil，部署 `CourseToken`，用 `cast` 查询余额并转账。
2. `forge test --match-path "test/ch07/*" -vv`（`DeployScript` 测试依赖你完成第 3 章）。
3. 如果有主网 RPC，运行分叉测试；试着把 `test_AaveV3SupplyAndBorrow` 的借款额改大，找出让 `borrow` revert 的临界值，再和 Aave 返回的 `ltv` 对照。

## 7.4 下一步学什么

- **Uniswap V3**：集中流动性、tick 数学；**V4**：hooks、单例合约、闪电记账。
- **可升级合约**：代理模式（Transparent / UUPS）、存储冲突、`initializer`。
- **ERC-4626** 收益金库标准、**ERC-721 / 1155**。
- **安全进阶**：做 [Damn Vulnerable DeFi](https://www.damnvulnerabledefi.xyz/) 和 [Ethernaut](https://ethernaut.openzeppelin.com/)；读 Code4rena / Sherlock 的审计报告；学习 Foundry 的不变量测试（`invariant_`）。
- **Gas 优化与汇编**：Yul、`forge snapshot`。
- **L2**：Arbitrum、Optimism、Base 等 rollup 的原理与差异。

## 小测验

1. `forge script` 不加 `--broadcast` 会发生什么？
2. 为什么在 fork 测试里推荐固定区块号？
3. fork 测试里 `deal(WETH, address(this), 10 ether)` 能直接改余额，原理是什么？这在真实链上能做到吗？
4. 部署到主网时，私钥应该如何管理？
5. 主网 USDC/WETH 交易对里，为什么 token0 是 USDC？

<details>
<summary>答案</summary>

1. 只在本地模拟执行，打印将要发送的交易和 gas 估算，不会真正上链。
2. 主网状态一直在变（储备、利率、价格），不固定区块的话每次结果都不同，测试会不稳定；固定后 Foundry 还能缓存 RPC 数据，速度更快。
3. `deal` 通过 `stdStorage` 找到代币合约里该地址余额所在的存储槽，然后用 `vm.store` 直接改写。这只是改了本地 fork 的状态，真实链上当然做不到。
4. 不写进代码、不提交 git；用硬件钱包（`--ledger`）或加密的 keystore（`cast wallet import` + `--account`）；生产合约的 owner 应该是多签而不是单个私钥。
5. Uniswap V2 Factory 按地址大小排序：`token0 < token1`。USDC 地址 `0xA0b8…` 小于 WETH 地址 `0xC02a…`。

</details>
