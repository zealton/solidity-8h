// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @notice 生产中更常见的写法：直接组合 OpenZeppelin 模块
/// - ERC20       : 标准实现
/// - ERC20Permit : EIP-2612，用链下签名代替 approve 交易（Uniswap、Aave 前端都在用）
/// - Ownable     : 最简单的权限控制
contract CourseToken is ERC20, ERC20Permit, Ownable {
    uint256 public constant CAP = 1_000_000e18;

    error CapExceeded(uint256 newSupply, uint256 cap);

    constructor(address initialOwner) ERC20("Course Token", "CRS") ERC20Permit("Course Token") Ownable(initialOwner) {}

    /// @notice 练习：只有 owner 能铸币，且铸造后总量不得超过 CAP
    function mint(address to, uint256 amount) external onlyOwner {
        // ===== TODO BEGIN =====
        // HINT: uint256 newSupply = totalSupply() + amount; 超过 CAP 就 revert CapExceeded(newSupply, CAP); 然后 _mint
        uint256 newSupply = totalSupply() + amount;
        if (newSupply > CAP) revert CapExceeded(newSupply, CAP);
        _mint(to, amount);
        // ===== TODO END =====
    }
}
