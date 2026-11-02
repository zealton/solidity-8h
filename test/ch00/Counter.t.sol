// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Counter} from "ex/ch00/Counter.sol";

contract CounterTest is Test {
    Counter counter;

    // 每个 test_ 函数运行前都会重新执行 setUp，测试之间状态互不影响
    function setUp() public {
        counter = new Counter();
    }

    function test_Increment() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

    function test_EmitsEvent() public {
        // expectEmit(检查topic1, topic2, topic3, 检查data)
        vm.expectEmit(false, false, false, true);
        emit Counter.NumberChanged(7);
        counter.setNumber(7);
    }

    // 练习检查
    function test_Decrement() public {
        counter.setNumber(2);
        counter.decrement();
        assertEq(counter.number(), 1);
    }

    function test_DecrementRevertsAtZero() public {
        vm.expectRevert(Counter.Underflow.selector);
        counter.decrement();
    }

    // 模糊测试：Foundry 会用随机 x 跑 256 次
    function testFuzz_SetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
