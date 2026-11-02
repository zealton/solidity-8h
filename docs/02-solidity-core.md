# 第 2 章　Solidity 核心语法（75 分钟）

**目标**：以"已会一门 C 系语言"为前提，快速掌握 Solidity 与众不同的部分，并用它实现 DeFi 里使用最广的合约之一：**WETH9**。

## 2.1 合约骨架

```solidity
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;              // 编译器版本

contract Vault {
    // 状态变量（存在 storage）
    address public owner;              // public 自动生成 getter: owner()
    mapping(address => uint256) public balanceOf;
    uint256 public constant FEE = 30;  // 常量：编译期内联，不占存储
    address public immutable token;    // 不可变量：构造时赋值，写进字节码

    event Deposited(address indexed user, uint256 amount);  // 事件：写日志，链下可订阅
    error NotOwner(address caller);                          // 自定义错误：比字符串省 gas

    modifier onlyOwner() {             // 修饰器：函数前后插入代码
        if (msg.sender != owner) revert NotOwner(msg.sender);
        _;                             // 被修饰函数体在这里执行
    }

    constructor(address token_) { owner = msg.sender; token = token_; }

    function deposit() external payable { ... }   // payable 才能收 ETH
    receive() external payable { ... }            // 纯 ETH 转账（无 calldata）时调用
    fallback() external payable { ... }           // 没匹配到任何函数时调用
}
```

## 2.2 类型速查

| 类型 | 说明 | 注意 |
|---|---|---|
| `uint256` / `int256` | 默认整数，`uint8`…`uint256` 步长 8 | **没有浮点数**，金额用最小单位（wei，1 ETH = 1e18 wei） |
| `address` / `address payable` | 20 字节 | `.balance`、`.call{value: x}("")` |
| `bool`、`bytes32`、`bytes4` | 定长 | 选择器就是 `bytes4` |
| `bytes`、`string` | 动态 | 尽量少在链上存字符串 |
| `T[]`、`T[N]` | 数组 | 遍历无界数组 = gas 炸弹 |
| `mapping(K => V)` | 哈希表 | **不能遍历、没有长度**，不存在的 key 返回 0 值 |
| `struct`、`enum` | 复合类型 | 小字段相邻放可以打包省存储 |

**定点数靠约定**：DeFi 普遍用 1e18 当 1（"WAD"），或 Uniswap 的 UQ112x112、Aave 的 1e27（"RAY"）。乘法后要除以精度，**先乘后除**避免精度丢失。

## 2.3 数据位置：storage / memory / calldata

引用类型（数组、结构体、bytes、string）必须声明位置：

```solidity
Position storage p = positions[user];  // 引用：修改 p 就是修改链上数据
Position memory  q = positions[user];  // 拷贝：修改 q 不影响链上，函数结束就丢
function f(uint256[] calldata xs)      // 外部函数参数用 calldata：只读、最省 gas
```

`test/ch02/Language.t.sol` 的 `test_StorageVsMemory` 演示了经典 bug：用 `memory` 改了个寂寞。

## 2.4 可见性与状态可变性

| 可见性 | 谁能调用 |
|---|---|
| `external` | 只能从外部调用（包括 `this.f()`） |
| `public` | 内外都行 |
| `internal` | 本合约和子合约（library 的 internal 函数会被内联） |
| `private` | 仅本合约 |

| 可变性 | 含义 |
|---|---|
| `view` | 只读状态 |
| `pure` | 不读也不写状态 |
| `payable` | 可以接收 ETH |
| 默认 | 可以修改状态 |

## 2.5 错误处理

```solidity
require(x > 0, "x must be positive");   // 老写法，字符串占字节码
if (x == 0) revert ZeroAmount();        // 推荐：自定义错误
assert(invariant);                      // 只用于"不可能发生"的内部错误（Panic）
```

- 0.8 起**算术溢出自动 revert**（Panic 0x11）。确定不会溢出时可以用 `unchecked { }` 省 gas。
- revert 会回滚当前调用的所有状态修改，并把错误数据向上冒泡。
- `try/catch` 只能捕获**外部调用**的失败。

## 2.6 发送 ETH 的三种方式

```solidity
payable(to).transfer(amount);           // 只转 2300 gas，失败 revert —— 不推荐
bool ok = payable(to).send(amount);     // 同上但返回 bool —— 不推荐
(bool ok, ) = to.call{value: amount}(""); // ✅ 推荐：转发全部 gas，必须检查 ok
```

`transfer/send` 的 2300 gas 限制在 EIP-1884 后会让很多合约钱包（如 Safe）收不到钱，所以现代代码都用 `call`，**并配合第 4 章的重入防护**。

## 2.7 继承与接口

```solidity
interface IERC20 { function transfer(address to, uint256 v) external returns (bool); }

contract MyToken is ERC20, Ownable {     // 多继承，C3 线性化，从右往左"更派生"
    constructor() ERC20("My", "MY") Ownable(msg.sender) {}
    function decimals() public pure override returns (uint8) { return 6; }  // 重写需 override
}
```

调用其他合约：`IERC20(tokenAddr).transfer(to, v)`。编译器会帮你编码 calldata、检查返回值。

## 2.8 真实代码：WETH9

以太坊原生 ETH 不是 ERC-20，没法统一用 `transferFrom` 处理。WETH9 把 ETH 1:1 包装成 ERC-20，至今是 DeFi 里被调用最多的合约之一。原版（Solidity 0.4.18）核心就这几行：

```solidity
function deposit() public payable {
    balanceOf[msg.sender] += msg.value;
    Deposit(msg.sender, msg.value);
}
function withdraw(uint wad) public {
    require(balanceOf[msg.sender] >= wad);
    balanceOf[msg.sender] -= wad;
    msg.sender.transfer(wad);
    Withdrawal(msg.sender, wad);
}
function totalSupply() public view returns (uint) {
    return this.balance;                 // 总供应量 = 合约持有的 ETH
}
function transferFrom(address src, address dst, uint wad) public returns (bool) {
    require(balanceOf[src] >= wad);
    if (src != msg.sender && allowance[src][msg.sender] != uint(-1)) {  // uint(-1) = 无限授权
        require(allowance[src][msg.sender] >= wad);
        allowance[src][msg.sender] -= wad;
    }
    ...
}
```

注意 `withdraw` 里**先扣余额、再转账**的顺序，这是它能安全运行 8 年的关键。

## 2.9 动手（30 分钟）

`src/ch02/WETH.sol` 是 WETH9 的 0.8 改写版。实现：
1. `deposit()`：记账 + 事件；
2. `withdraw(uint256)`：检查余额（自定义错误带参数）→ 扣余额 → `call` 转 ETH → 检查结果 → 事件。

```bash
forge test --match-path "test/ch02/*" -vv
```

然后读 `test/ch02/Language.t.sol` 的 6 个演示，每个都改一改，观察测试如何变红。

## 小测验

1. `constant` 和 `immutable` 的区别？各自适合什么场景？
2. 为什么 `mapping` 不能遍历？如果需要"所有持币人列表"怎么办？
3. 写出下面代码执行后 `positions[user].amount` 的值，并解释：
   ```solidity
   Position memory p = positions[user];  // 原值 100
   p.amount = 0;
   ```
4. 为什么推荐 `call{value: x}("")` 而不是 `transfer(x)`？用 `call` 时必须注意什么？
5. `uint256 x = 5 / 2 * 2;` 的结果是多少？在计算利率时应该怎样写乘除顺序？
6. 一个合约没有 `receive()` 也没有 `payable fallback()`，别人用 `call{value: 1 ether}("")` 给它转账会怎样？（参考 `test_WithdrawToContractWithoutReceiveReverts`）
7. 自定义错误比 `require(cond, "string")` 好在哪？

<details>
<summary>答案</summary>

1. `constant` 编译期就确定，直接内联进字节码；`immutable` 在构造函数里赋值一次，之后写进运行时字节码。都不占 storage、读取几乎免费。固定参数（费率、精度）用 constant，部署时才知道的地址（代币地址、Factory）用 immutable。
2. mapping 只存哈希后的槽位，不记录有哪些 key。需要列表时另存一个数组，或者链下通过监听 `Transfer` 事件建索引（The Graph、Dune 就是这么做的）。
3. 仍是 100。`memory` 是拷贝，修改不写回 storage。
4. `transfer` 只给 2300 gas，接收方是合约钱包时可能失败。用 `call` 必须：检查返回的 `ok`；遵循 CEI 或加重入锁，因为对方拿到了全部 gas，可以回调你。
5. 4（整数除法截断：5/2=2，再×2）。应该先乘后除：`a * rate / 1e18`，并注意乘法不溢出。
6. 调用失败，`ok` 为 false（高层调用则直接 revert）。WETH 的 `withdraw` 因此 revert `EthTransferFailed`。
7. 更省 gas（字节码里不存字符串，revert 数据只有 4 字节选择器 + 参数），还能携带结构化参数（如余额、所需金额），方便前端和测试精确匹配。

</details>
