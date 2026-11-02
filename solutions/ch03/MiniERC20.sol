// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 从零写一个 ERC-20，错误名与 OpenZeppelin v5 (IERC20Errors / ERC-6093) 保持一致，
/// 写完后可以对照 lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol 看看差在哪
contract MiniERC20 {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidSpender(address spender);

    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_, uint256 initialSupply) {
        name = name_;
        symbol = symbol_;
        _mint(msg.sender, initialSupply);
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice 练习 1：设置授权。spender 为 0 地址时 revert ERC20InvalidSpender(address(0))
    function approve(address spender, uint256 value) external returns (bool) {
        // ===== TODO BEGIN =====
        // HINT: 检查 spender -> allowance[msg.sender][spender] = value -> emit Approval -> return true
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
        // ===== TODO END =====
    }

    /// @notice 练习 2：代扣转账。
    /// - 额度 == type(uint256).max 时视为无限授权，不扣减（与 OZ 的 _spendAllowance 一致）
    /// - 额度不足 revert ERC20InsufficientAllowance(msg.sender, 当前额度, value)
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        // ===== TODO BEGIN =====
        // HINT: 先处理 allowance（注意无限授权），再调用 _transfer(from, to, value)
        uint256 current = allowance[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert ERC20InsufficientAllowance(msg.sender, current, value);
            unchecked {
                allowance[from][msg.sender] = current - value;
            }
        }
        _transfer(from, to, value);
        return true;
        // ===== TODO END =====
    }

    /// @notice 练习 3：内部转账。to 为 0 地址 revert ERC20InvalidReceiver(address(0))；
    /// 余额不足 revert ERC20InsufficientBalance(from, 余额, value)；最后 emit Transfer
    function _transfer(address from, address to, uint256 value) internal {
        // ===== TODO BEGIN =====
        // HINT: 检查 to -> 检查余额 -> 扣 from 加 to（扣减可用 unchecked，为什么安全？）-> emit
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        unchecked {
            balanceOf[from] = fromBalance - value; // 上一行已保证不会下溢
            balanceOf[to] += value; // 总和 <= totalSupply，不会溢出
        }
        emit Transfer(from, to, value);
        // ===== TODO END =====
    }

    function _mint(address to, uint256 value) internal {
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        totalSupply += value;
        unchecked {
            balanceOf[to] += value;
        }
        emit Transfer(address(0), to, value);
    }
}
