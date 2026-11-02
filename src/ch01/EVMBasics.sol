// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 第 1 章练习：用代码复现 EVM 的三个"底层公式"
library EVMBasics {
    /// @notice 函数选择器 = keccak256("函数签名") 的前 4 字节
    /// 例：selector("transfer(address,uint256)") == 0xa9059cbb
    function selector(string memory signature) internal pure returns (bytes4) {
        // ===== TODO: 在这里写你的代码 =====
        // HINT: bytes4(keccak256(bytes(signature)))
        revert("TODO");
        // ===== TODO END =====
    }

    /// @notice mapping(address => uint256) 声明在第 `slot` 个存储槽时，
    /// key 对应的值存放在 keccak256(abi.encode(key, slot))
    function mappingSlot(address key, uint256 slot) internal pure returns (bytes32) {
        // ===== TODO: 在这里写你的代码 =====
        // HINT: keccak256(abi.encode(key, slot))
        revert("TODO");
        // ===== TODO END =====
    }

    /// @notice CREATE2 地址 = keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode)) 的后 20 字节
    /// Uniswap V2 的 pairFor() 就是用这个公式在链下/链上算出交易对地址，而不用查询 Factory
    function create2Address(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        // ===== TODO: 在这里写你的代码 =====
        // HINT: address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))))
        revert("TODO");
        // ===== TODO END =====
    }
}
