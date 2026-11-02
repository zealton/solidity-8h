// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, stdError} from "forge-std/Test.sol";

/// 第 2 章语言要点演示：都可以直接运行，改一改看看结果怎么变
contract Box {
    struct Position {
        uint128 amount;
        uint64 openedAt;
        bool active;
    }

    mapping(address => Position) public positions;
    uint256[] public history;

    function open(uint128 amount) external {
        positions[msg.sender] = Position(amount, uint64(block.timestamp), true);
        history.push(amount);
    }

    /// storage 引用：直接改链上数据
    function addViaStorage(uint128 x) external {
        Position storage p = positions[msg.sender];
        p.amount += x;
    }

    /// memory 拷贝：只改了内存里的副本，函数结束就丢了 —— 经典 bug
    /// 编译器会提示"可以声明为 view"——这本身就说明它没有修改任何状态
    function addViaMemory(uint128 x) external view {
        Position memory p = positions[msg.sender];
        p.amount += x;
    }

    function wouldRevert() external pure {
        revert("nope");
    }
}

contract LanguageTest is Test {
    Box box;

    function setUp() public {
        box = new Box();
        box.open(100);
    }

    function test_StorageVsMemory() public {
        box.addViaMemory(50);
        (uint128 amount,,) = box.positions(address(this));
        assertEq(amount, 100); // 没变！

        box.addViaStorage(50);
        (amount,,) = box.positions(address(this));
        assertEq(amount, 150);
    }

    /// 0.8 起算术默认检查溢出，溢出会 revert Panic(0x11)
    function test_CheckedArithmetic() public {
        vm.expectRevert(stdError.arithmeticError);
        this.add(type(uint256).max, 1);
    }

    function add(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }

    /// unchecked 关闭检查：省 gas，但会回绕。Uniswap V2 的价格累加器就依赖这种回绕
    function test_UncheckedWraps() public pure {
        uint256 x = type(uint256).max;
        unchecked {
            x += 1;
        }
        assertEq(x, 0);
    }

    /// try/catch 只能捕获外部调用的失败
    function test_TryCatch() public {
        try box.wouldRevert() {
            fail();
        } catch Error(string memory reason) {
            assertEq(reason, "nope");
        }
    }

    /// abi.encodePacked 对动态类型会"粘连"，可能产生哈希碰撞；做签名/哈希请用 abi.encode
    function test_EncodePackedCollision() public pure {
        assertEq(keccak256(abi.encodePacked("ab", "c")), keccak256(abi.encodePacked("a", "bc")));
        assertTrue(keccak256(abi.encode("ab", "c")) != keccak256(abi.encode("a", "bc")));
    }

    /// 结构体打包：uint128 + uint64 + bool 共 25 字节，挤在同一个 32 字节槽里
    function test_StructPacking() public view {
        bytes32 slot = keccak256(abi.encode(address(this), uint256(0)));
        bytes32 nextSlot = bytes32(uint256(slot) + 1);
        assertTrue(vm.load(address(box), slot) != bytes32(0));
        assertEq(vm.load(address(box), nextSlot), bytes32(0)); // 第二个槽是空的
    }
}
