// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CourseToken} from "ex/ch03/CourseToken.sol";

/// 模拟主网 USDT：transfer 不返回 bool（不符合 ERC-20 标准，但真实存在）
contract NoReturnToken {
    mapping(address => uint256) public balanceOf;

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
    }

    function transfer(address to, uint256 v) external {
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
    }
}

contract CourseTokenTest is Test {
    using SafeERC20 for IERC20;

    CourseToken token;
    address owner = makeAddr("owner");
    uint256 alicePk = 0xA11CE;
    address alice = vm.addr(alicePk);
    address spender = makeAddr("spender");

    function setUp() public {
        token = new CourseToken(owner);
    }

    function test_OwnerCanMint() public {
        vm.prank(owner);
        token.mint(alice, 100e18);
        assertEq(token.balanceOf(alice), 100e18);
    }

    function test_NonOwnerCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vm.prank(alice);
        token.mint(alice, 1);
    }

    function test_CapEnforced() public {
        vm.startPrank(owner);
        token.mint(alice, token.CAP());
        vm.expectRevert(abi.encodeWithSelector(CourseToken.CapExceeded.selector, token.CAP() + 1, token.CAP()));
        token.mint(alice, 1);
        vm.stopPrank();
    }

    /// EIP-2612：alice 只在链下签名，spender 拿签名上链完成授权，alice 不花 gas
    function test_Permit() public {
        uint256 value = 50e18;
        uint256 deadline = block.timestamp + 1 hours;
        bytes32 PERMIT_TYPEHASH =
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, alice, spender, value, token.nonces(alice), deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePk, digest);

        vm.prank(spender); // 谁提交都可以
        token.permit(alice, spender, value, deadline, v, r, s);

        assertEq(token.allowance(alice, spender), value);
        assertEq(token.nonces(alice), 1); // nonce 防止签名重放
    }

    /// 为什么协议都用 SafeERC20：USDT 这类代币 transfer 不返回值，
    /// 直接按 IERC20 接口调用会因"返回数据解码失败"而 revert
    function test_SafeERC20HandlesNoReturnTokens() public {
        NoReturnToken usdt = new NoReturnToken();
        usdt.mint(address(this), 100);

        vm.expectRevert();
        this.naiveTransfer(address(usdt), alice, 10);

        IERC20(address(usdt)).safeTransfer(alice, 10);
        assertEq(usdt.balanceOf(alice), 10);
    }

    function naiveTransfer(address t, address to, uint256 v) external {
        IERC20(t).transfer(to, v);
    }
}
