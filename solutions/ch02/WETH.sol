// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice WETH9 的 0.8 改写版。原版（2017，主网 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2）
/// 至今锁着数百万 ETH，是整个 DeFi 的"ETH 适配器"：把原生 ETH 包装成 ERC-20。
/// 与原版的差别：require 字符串 -> 自定义错误；transfer() 改用 call。
contract WETH {
    string public constant name = "Wrapped Ether";
    string public constant symbol = "WETH";
    uint8 public constant decimals = 18;

    event Approval(address indexed src, address indexed guy, uint256 wad);
    event Transfer(address indexed src, address indexed dst, uint256 wad);
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    error InsufficientBalance(uint256 balance, uint256 needed);
    error InsufficientAllowance(uint256 allowance, uint256 needed);
    error EthTransferFailed();

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    /// 直接向合约转 ETH（没有 calldata）时触发
    receive() external payable {
        deposit();
    }

    /// @notice 练习 1：存入 ETH，1:1 记账，并 emit Deposit
    function deposit() public payable {
        // ===== TODO BEGIN =====
        // HINT: balanceOf[msg.sender] += msg.value; emit Deposit(msg.sender, msg.value);
        balanceOf[msg.sender] += msg.value;
        emit Deposit(msg.sender, msg.value);
        // ===== TODO END =====
    }

    /// @notice 练习 2：销毁 wad 个 WETH 并把 ETH 还给调用者
    /// 余额不足时 revert InsufficientBalance(余额, wad)；ETH 发送失败 revert EthTransferFailed()
    /// 注意顺序：先改状态，再转 ETH（Checks-Effects-Interactions，第 4 章详解）
    function withdraw(uint256 wad) public {
        // ===== TODO BEGIN =====
        // HINT: 检查余额 -> 扣余额 -> (bool ok,) = msg.sender.call{value: wad}(""); -> emit Withdrawal
        uint256 bal = balanceOf[msg.sender];
        if (bal < wad) revert InsufficientBalance(bal, wad);
        balanceOf[msg.sender] = bal - wad;
        (bool ok,) = msg.sender.call{value: wad}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawal(msg.sender, wad);
        // ===== TODO END =====
    }

    /// 总供应量 = 合约持有的 ETH，永远 1:1
    function totalSupply() public view returns (uint256) {
        return address(this).balance;
    }

    function approve(address guy, uint256 wad) public returns (bool) {
        allowance[msg.sender][guy] = wad;
        emit Approval(msg.sender, guy, wad);
        return true;
    }

    function transfer(address dst, uint256 wad) public returns (bool) {
        return transferFrom(msg.sender, dst, wad);
    }

    function transferFrom(address src, address dst, uint256 wad) public returns (bool) {
        uint256 bal = balanceOf[src];
        if (bal < wad) revert InsufficientBalance(bal, wad);

        // 原版 WETH9 的写法：授权额度为 uint256 最大值时视为"无限授权"，不扣减
        if (src != msg.sender && allowance[src][msg.sender] != type(uint256).max) {
            uint256 allowed = allowance[src][msg.sender];
            if (allowed < wad) revert InsufficientAllowance(allowed, wad);
            allowance[src][msg.sender] = allowed - wad;
        }

        balanceOf[src] = bal - wad;
        balanceOf[dst] += wad;
        emit Transfer(src, dst, wad);
        return true;
    }
}
