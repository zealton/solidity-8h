// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {EVMBasics} from "ex/ch01/EVMBasics.sol";

/// 存储布局：slot0 = owner(20字节) , slot1 = balances 的"占位槽"
contract Layout {
    address public owner = address(0xBEEF);
    mapping(address => uint256) public balances;

    function set(address who, uint256 v) external {
        balances[who] = v;
    }
}

contract Dummy {
    uint256 public x = 1;
}

contract WhoCalls {
    function who() external view returns (address sender, address origin) {
        return (msg.sender, tx.origin);
    }
}

contract EVMBasicsTest is Test {
    address alice = makeAddr("alice");

    // ---------- 练习检查 ----------

    function test_Selector() public pure {
        assertEq(EVMBasics.selector("transfer(address,uint256)"), bytes4(0xa9059cbb));
        assertEq(EVMBasics.selector("transfer(address,uint256)"), IERC20.transfer.selector);
        assertEq(EVMBasics.selector("approve(address,uint256)"), IERC20.approve.selector);
    }

    function test_MappingSlot() public {
        Layout l = new Layout();
        l.set(alice, 42);
        // vm.load 直接读取任意合约的任意存储槽 —— 链上没有"私有"数据
        bytes32 raw = vm.load(address(l), EVMBasics.mappingSlot(alice, 1));
        assertEq(uint256(raw), 42);
        // slot0 里是 owner
        assertEq(address(uint160(uint256(vm.load(address(l), bytes32(0))))), address(0xBEEF));
    }

    function test_Create2Address() public {
        bytes32 salt = keccak256("course");
        address predicted = EVMBasics.create2Address(address(this), salt, keccak256(type(Dummy).creationCode));
        Dummy d = new Dummy{salt: salt}();
        assertEq(address(d), predicted);
    }

    // ---------- 演示（无需修改，读懂即可） ----------

    /// CREATE 地址只取决于 (部署者地址, 部署者 nonce)
    function test_CreateAddressDependsOnNonce() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        Dummy d = new Dummy();
        assertEq(address(d), predicted);
    }

    /// msg.sender 是直接调用者；tx.origin 永远是签名交易的 EOA
    function test_MsgSenderVsTxOrigin() public {
        WhoCalls w = new WhoCalls();
        vm.prank(alice, alice); // 下一次调用的 msg.sender 和 tx.origin 都是 alice
        (address sender, address origin) = w.who();
        assertEq(sender, alice);
        assertEq(origin, alice);

        // 测试合约自己调用：sender 是测试合约，origin 是默认的 EOA
        (sender, origin) = w.who();
        assertEq(sender, address(this));
        assertTrue(origin != address(this));
    }

    /// 写一个从 0 变非 0 的存储槽 (~20k gas) 远比改写已有值 (~2.9k gas) 贵
    function test_SstoreGasCost() public {
        Layout l = new Layout();
        uint256 g0 = gasleft();
        l.set(alice, 1); // 0 -> 非0
        uint256 firstWrite = g0 - gasleft();
        g0 = gasleft();
        l.set(alice, 2); // 非0 -> 非0
        uint256 secondWrite = g0 - gasleft();
        console.log("0->1 gas:", firstWrite, " 1->2 gas:", secondWrite);
        assertGt(firstWrite, secondWrite + 10_000);
    }

    /// 区块上下文：时间与高度可以在测试里随意操控
    function test_BlockContext() public {
        vm.warp(1_700_000_000);
        vm.roll(19_000_000);
        assertEq(block.timestamp, 1_700_000_000);
        assertEq(block.number, 19_000_000);
    }

    /// ETH 余额与转账
    function test_EthTransfer() public {
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (bool ok,) = payable(address(0xCAFE)).call{value: 0.4 ether}("");
        assertTrue(ok);
        assertEq(alice.balance, 0.6 ether);
        assertEq(address(0xCAFE).balance, 0.4 ether);
    }
}
