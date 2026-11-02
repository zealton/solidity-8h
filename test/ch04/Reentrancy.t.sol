// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {VulnerableBank} from "ex/ch04/VulnerableBank.sol";
import {SafeBank} from "ex/ch04/SafeBank.sol";
import {Attacker, IBank} from "ex/ch04/Attacker.sol";

interface ISafeBank {
    function deposit() external payable;
    function withdraw() external;
    function balances(address) external view returns (uint256);
}

contract ReentrancyTest is Test {
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address hacker = makeAddr("hacker");

    function _fund(address bank) internal {
        vm.deal(alice, 5 ether);
        vm.deal(bob, 5 ether);
        vm.prank(alice);
        IBank(bank).deposit{value: 5 ether}();
        vm.prank(bob);
        IBank(bank).deposit{value: 5 ether}();
    }

    /// 演示：1 ETH 本金掏空 10 ETH 的银行
    function test_AttackDrainsVulnerableBank() public {
        VulnerableBank bank = new VulnerableBank();
        _fund(address(bank));

        vm.deal(hacker, 1 ether);
        vm.startPrank(hacker);
        Attacker attacker = new Attacker(IBank(address(bank)));
        attacker.attack{value: 1 ether}();
        vm.stopPrank();

        console.log("reentries:", attacker.reentries());
        assertEq(address(bank).balance, 0);
        assertEq(hacker.balance, 11 ether);
    }

    // ---------- 练习检查 ----------

    function test_SafeBankNormalWithdraw() public {
        SafeBank bank = new SafeBank();
        _fund(address(bank));
        vm.prank(alice);
        ISafeBank(address(bank)).withdraw();
        assertEq(alice.balance, 5 ether);
        assertEq(ISafeBank(address(bank)).balances(alice), 0);
    }

    function test_SafeBankWithdrawWithoutBalanceReverts() public {
        SafeBank bank = new SafeBank();
        vm.expectRevert(SafeBank.NoBalance.selector);
        vm.prank(alice);
        ISafeBank(address(bank)).withdraw();
    }

    function test_AttackFailsOnSafeBank() public {
        SafeBank bank = new SafeBank();
        _fund(address(bank));

        vm.deal(hacker, 1 ether);
        vm.startPrank(hacker);
        Attacker attacker = new Attacker(IBank(address(bank)));
        // 重入的那次 withdraw 会失败 -> receive() revert -> call 返回 false -> SendFailed，整笔交易回滚
        vm.expectRevert(SafeBank.SendFailed.selector);
        attacker.attack{value: 1 ether}();
        vm.stopPrank();

        assertEq(address(bank).balance, 10 ether);
    }
}
