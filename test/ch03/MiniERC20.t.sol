// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MiniERC20} from "ex/ch03/MiniERC20.sol";

contract MiniERC20Test is Test {
    MiniERC20 token;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        // 构造函数把初始供应 mint 给部署者：这里让 alice 部署，她就拿到全部 100 枚
        vm.prank(alice);
        token = new MiniERC20("Mini", "MINI", 100e18);
    }

    function test_Transfer() public {
        vm.expectEmit(true, true, false, true);
        emit MiniERC20.Transfer(alice, bob, 30e18);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 30e18));
        assertEq(token.balanceOf(alice), 70e18);
        assertEq(token.balanceOf(bob), 30e18);
    }

    function test_TransferInsufficientBalance() public {
        vm.expectRevert(abi.encodeWithSelector(MiniERC20.ERC20InsufficientBalance.selector, alice, 100e18, 101e18));
        vm.prank(alice);
        token.transfer(bob, 101e18);
    }

    function test_TransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(MiniERC20.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(alice);
        token.transfer(address(0), 1);
    }

    function test_ApproveAndTransferFrom() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true);
        emit MiniERC20.Approval(alice, bob, 50e18);
        token.approve(bob, 50e18);

        vm.prank(bob);
        token.transferFrom(alice, bob, 20e18);
        assertEq(token.allowance(alice, bob), 30e18);
        assertEq(token.balanceOf(bob), 20e18);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(MiniERC20.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    function test_TransferFromInsufficientAllowance() public {
        vm.prank(alice);
        token.approve(bob, 10e18);
        vm.expectRevert(abi.encodeWithSelector(MiniERC20.ERC20InsufficientAllowance.selector, bob, 10e18, 11e18));
        vm.prank(bob);
        token.transferFrom(alice, bob, 11e18);
    }

    function test_InfiniteAllowance() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(alice, bob, 60e18);
        assertEq(token.allowance(alice, bob), type(uint256).max);
    }

    /// 不变量：转账不改变总量，双方余额之和守恒
    function testFuzz_TransferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != alice);
        amount = bound(amount, 0, 100e18);
        uint256 before = token.balanceOf(alice) + token.balanceOf(to);
        vm.prank(alice);
        token.transfer(to, amount);
        assertEq(token.balanceOf(alice) + token.balanceOf(to), before);
        assertEq(token.totalSupply(), 100e18);
    }
}
