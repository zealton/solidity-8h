// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 有重入漏洞的银行 —— 2016 年 The DAO 被盗约 360 万 ETH 的同款问题。
/// 问题：先把 ETH 发出去（Interaction），后清零余额（Effect）。
/// 接收方合约在 receive() 里再次调用 withdraw()，此时余额还没清零。
/// 本文件是演示用的"靶子"，请不要修改。
contract VulnerableBank {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw() external {
        uint256 amount = balances[msg.sender];
        require(amount > 0, "no balance");

        (bool ok,) = msg.sender.call{value: amount}(""); // ← 外部调用，控制权交给了对方
        require(ok, "send failed");

        balances[msg.sender] = 0; // ← 太晚了
    }
}
