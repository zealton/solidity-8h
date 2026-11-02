// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {WETH} from "ex/ch02/WETH.sol";

/// 一个拒收 ETH 的合约（没有 receive / fallback）
contract NoReceive {
    function withdrawFrom(WETH weth, uint256 wad) external {
        weth.withdraw(wad);
    }

    function depositTo(WETH weth) external payable {
        weth.deposit{value: msg.value}();
    }
}

contract WETHTest is Test {
    WETH weth;
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    function setUp() public {
        weth = new WETH();
        vm.deal(alice, 10 ether);
    }

    function test_Deposit() public {
        vm.expectEmit(true, false, false, true);
        emit WETH.Deposit(alice, 1 ether);
        vm.prank(alice);
        weth.deposit{value: 1 ether}();

        assertEq(weth.balanceOf(alice), 1 ether);
        assertEq(weth.totalSupply(), 1 ether);
    }

    function test_ReceiveDeposits() public {
        vm.prank(alice);
        (bool ok,) = address(weth).call{value: 2 ether}("");
        assertTrue(ok);
        assertEq(weth.balanceOf(alice), 2 ether);
    }

    function test_Withdraw() public {
        vm.startPrank(alice);
        weth.deposit{value: 3 ether}();
        vm.expectEmit(true, false, false, true);
        emit WETH.Withdrawal(alice, 1 ether);
        weth.withdraw(1 ether);
        vm.stopPrank();

        assertEq(weth.balanceOf(alice), 2 ether);
        assertEq(alice.balance, 8 ether);
        assertEq(weth.totalSupply(), 2 ether);
    }

    function test_WithdrawTooMuchReverts() public {
        vm.startPrank(alice);
        weth.deposit{value: 1 ether}();
        // 自定义错误带参数时，用 abi.encodeWithSelector 精确匹配
        vm.expectRevert(abi.encodeWithSelector(WETH.InsufficientBalance.selector, 1 ether, 2 ether));
        weth.withdraw(2 ether);
        vm.stopPrank();
    }

    function test_WithdrawToContractWithoutReceiveReverts() public {
        NoReceive nr = new NoReceive();
        nr.depositTo{value: 1 ether}(weth);
        vm.expectRevert(WETH.EthTransferFailed.selector);
        nr.withdrawFrom(weth, 1 ether);
    }

    function test_InfiniteApprovalIsNotDecremented() public {
        vm.prank(alice);
        weth.deposit{value: 5 ether}();
        vm.prank(alice);
        weth.approve(bob, type(uint256).max);

        vm.prank(bob);
        weth.transferFrom(alice, bob, 2 ether);

        assertEq(weth.balanceOf(bob), 2 ether);
        assertEq(weth.allowance(alice, bob), type(uint256).max);
    }

    /// 不变量：任何存取序列之后，totalSupply 都等于合约 ETH 余额，且余额正确
    function testFuzz_DepositWithdraw(uint96 depositAmt, uint96 withdrawAmt) public {
        vm.assume(withdrawAmt <= depositAmt);
        vm.deal(alice, depositAmt);
        vm.startPrank(alice);
        weth.deposit{value: depositAmt}();
        weth.withdraw(withdrawAmt);
        vm.stopPrank();
        assertEq(weth.balanceOf(alice), uint256(depositAmt) - withdrawAmt);
        assertEq(weth.totalSupply(), address(weth).balance);
        assertEq(alice.balance, withdrawAmt);
    }
}
