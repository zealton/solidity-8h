// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 第 0 章：最小合约，用来熟悉 Foundry 的 build / test 流程
contract Counter {
    uint256 public number;

    event NumberChanged(uint256 newNumber);

    error Underflow();

    function setNumber(uint256 newNumber) external {
        number = newNumber;
        emit NumberChanged(newNumber);
    }

    function increment() external {
        number++;
        emit NumberChanged(number);
    }

    /// @notice 练习：实现 decrement，number 为 0 时用自定义错误 Underflow() revert
    function decrement() external {
        // ===== TODO: 在这里写你的代码 =====
        // HINT: if (number == 0) revert Underflow(); 然后自减并 emit 事件
        revert("TODO");
        // ===== TODO END =====
    }
}
