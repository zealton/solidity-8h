# 第 3 章　ERC-20 与 OpenZeppelin（60 分钟）

**目标**：理解 ERC-20 接口每个函数的意义和坑，从零实现一遍，再学会用 OpenZeppelin 写生产级代币，掌握 Permit 和 SafeERC20 这两个所有协议都在用的工具。

## 3.1 ERC-20 接口（EIP-20）

```solidity
interface IERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}
// 可选：name() / symbol() / decimals()
```

本质：**代币就是合约里的一个 `mapping(address => uint256)`**。你"拥有"代币，只是代币合约里记了你的余额。

### approve + transferFrom：DeFi 的基本交互模式

合约无法"主动从你钱包扣钱"。想把 USDC 存进 Aave，需要两步：

```
1. 用户 → USDC.approve(AavePool, 1000)       // 授权 Aave 最多动用 1000
2. 用户 → AavePool.supply(USDC, 1000)
             └→ USDC.transferFrom(用户, AavePool, 1000)   // Aave 在内部扣款
```

### 几个必须知道的细节

- **decimals 只是显示用的**。USDC/USDT 是 6 位，WETH/DAI 是 18 位。合约之间做数学运算时一定要换算精度，这是真实 bug 的高发区。
- **无限授权**：`approve(spender, type(uint256).max)` 很常见（省得每次授权），OZ 和 WETH9 都对这个值特殊处理：不扣减。代价是 spender 合约若被攻破，你的币全部有风险。
- **approve 抢跑问题**：把授权从 100 改成 50，spender 可以抢先花掉 100 再花 50。缓解：先改成 0 再改，或用 Permit。
- **转给 0 地址**：OZ 禁止，销毁要用 `_burn`。

## 3.2 真实代码：OpenZeppelin v5 的 `_update`

OZ v5 把所有余额变化（转账、铸造、销毁）统一到一个函数里（lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol）：

```solidity
function _update(address from, address to, uint256 value) internal virtual {
    if (from == address(0)) {
        // 铸造：总量增加
        _totalSupply += value;          // 溢出检查在这里，保证下面不会溢出
    } else {
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) {
            revert ERC20InsufficientBalance(from, fromBalance, value);
        }
        unchecked {
            // 不会下溢：上面已检查 value <= fromBalance <= totalSupply
            _balances[from] = fromBalance - value;
        }
    }

    if (to == address(0)) {
        unchecked {
            // 销毁：不会下溢，value <= totalSupply
            _totalSupply -= value;
        }
    } else {
        unchecked {
            // 不会溢出：所有余额之和 <= totalSupply
            _balances[to] += value;
        }
    }

    emit Transfer(from, to, value);
}
```

学习要点：
1. **一个入口**：想给代币加"转账手续费 / 黑名单 / 暂停"，只需 override `_update`。
2. **`unchecked` 的正确用法**：每处都写了为什么不会溢出。
3. **ERC-6093 标准错误**：`ERC20InsufficientBalance(sender, balance, needed)`。我们的练习沿用同样的错误名。

## 3.3 真实代码：EIP-2612 Permit

`approve` 需要用户单独发一笔交易。Permit 让用户**链下签名**，任何人拿签名上链完成授权，于是"授权 + 存款"可以在一笔交易里完成。Uniswap、Aave、1inch 前端都在用。

```solidity
// OZ ERC20Permit.permit 核心
bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
bytes32 hash = _hashTypedDataV4(structHash);   // EIP-712: keccak256("\x19\x01" ++ domainSeparator ++ structHash)
address signer = ECDSA.recover(hash, v, r, s);
if (signer != owner) revert ERC2612InvalidSigner(signer, owner);
_approve(owner, spender, value);
```

- `nonce` 防重放；`deadline` 防签名被长期滥用；`DOMAIN_SEPARATOR` 含链 ID 和合约地址，防止跨链/跨合约重放。
- `test_Permit` 用 `vm.sign` 在测试里完整走了一遍签名流程。

## 3.4 真实代码：SafeERC20 与"不标准"的 USDT

主网 USDT 的 `transfer` **没有返回值**（不符合 EIP-20）。如果按标准接口 `IERC20(usdt).transfer(...)` 调用，Solidity 会尝试解码 32 字节的 bool 返回值，拿不到就 revert。还有些代币失败时返回 `false` 而不是 revert。

OZ 的 `SafeERC20` 用底层 call 兼容这些情况：

```solidity
using SafeERC20 for IERC20;
token.safeTransfer(to, amount);          // 无返回值 → 视为成功；返回 false → revert
token.safeTransferFrom(from, to, amount);
token.forceApprove(spender, amount);     // 兼容 USDT "必须先归零再 approve" 的怪癖
```

**规则：协议代码里和任意代币交互，一律用 SafeERC20。** Uniswap V2 自己实现了一个同样作用的 `_safeTransfer`。

## 3.5 动手（30 分钟）

**练习 1：`src/ch03/MiniERC20.sol`** —— 从零实现 `approve`、`transferFrom`、`_transfer`。错误名和 OZ 一致，写完对照 OZ 源码。

**练习 2：`src/ch03/CourseToken.sol`** —— 组合 OZ 的 `ERC20 + ERC20Permit + Ownable`，实现带上限的 `mint`。

```bash
forge test --match-path "test/ch03/*" -vv
```

思考题：`testFuzz_TransferConservesSupply` 里为什么要 `vm.assume(to != alice)`？去掉会怎样？

## 小测验

1. 用户想把 100 USDC 存入某协议，为什么需要两笔交易？有什么办法变成一笔？
2. USDC 是 6 位小数。合约收到 `1_000_000` 个单位的 USDC，代表多少美元？
3. OZ 的 `_update` 里，为什么 `_balances[to] += value` 可以放在 `unchecked` 里？
4. 为什么 Permit 签名里要包含 `nonce`、`deadline` 和 `DOMAIN_SEPARATOR`？分别防什么？
5. 直接 `IERC20(usdt).transfer(to, x)` 调用主网 USDT 会发生什么？怎么解决？
6. 用 OZ 写一个"每笔转账收 1% 手续费给国库"的代币，应该 override 哪个函数？
7. 授权额度设为 `type(uint256).max` 有什么好处和风险？

<details>
<summary>答案</summary>

1. 合约不能主动扣款，需要先 `approve` 再由协议 `transferFrom`。用 EIP-2612 Permit（链下签名 + 协议在同一笔交易里调用 `permit` 和 `transferFrom`），或 Uniswap 的 Permit2。
2. 1 美元（1_000_000 / 10⁶）。
3. 所有账户余额之和不超过 `_totalSupply`，而 `_totalSupply` 在铸造时已经做过溢出检查，所以任何单个余额都不会溢出。
4. nonce 防同一签名被重复使用；deadline 限制签名有效期；DOMAIN_SEPARATOR 绑定链 ID 和合约地址，防止签名在别的链或别的代币上被重放。
5. 会 revert，因为 USDT 不返回 bool，ABI 解码失败。使用 OZ 的 `SafeERC20.safeTransfer`。
6. `_update(from, to, value)`：普通转账（from 和 to 都非 0）时，先 `super._update(from, treasury, fee)`，再 `super._update(from, to, value - fee)`。
7. 好处：省去每次授权的交易和 gas，体验好。风险：被授权合约若有漏洞或被升级成恶意代码，可以转走你全部该代币（历史上多次发生）。

</details>
