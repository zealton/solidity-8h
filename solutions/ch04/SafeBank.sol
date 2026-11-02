// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @notice 练习：修复重入。两道防线都要用上：
/// 1. Checks-Effects-Interactions：先检查、再改状态、最后外部调用
/// 2. OpenZeppelin ReentrancyGuard 的 nonReentrant 修饰器
contract SafeBank is ReentrancyGuard {
    mapping(address => uint256) public balances;

    error NoBalance();
    error SendFailed();

    event Withdrawn(address indexed user, uint256 amount);

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    // ===== TODO BEGIN =====
    // HINT: 把下面这个桩函数改成 nonReentrant，并按 CEI 实现：
    // HINT: 读余额 -> 为 0 则 revert NoBalance() -> 先清零 -> 再 call 转账 -> 失败 revert SendFailed() -> emit Withdrawn
    // STUB: function withdraw() external {
    // STUB:     revert("TODO");
    // STUB: }
    function withdraw() external nonReentrant {
        uint256 amount = balances[msg.sender]; // Checks
        if (amount == 0) revert NoBalance();

        balances[msg.sender] = 0; // Effects

        (bool ok,) = msg.sender.call{value: amount}(""); // Interactions
        if (!ok) revert SendFailed();
        emit Withdrawn(msg.sender, amount);
    }
    // ===== TODO END =====
}
