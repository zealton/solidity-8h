// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 第 1 章练习：用代码复现 EVM 的三个"底层公式"
library EVMBasics {
    /// @notice 函数选择器 = keccak256("函数签名") 的前 4 字节
    /// 例：selector("transfer(address,uint256)") == 0xa9059cbb
    function selector(string memory signature) internal pure returns (bytes4) {
        // ===== TODO BEGIN =====
        // HINT: bytes4(keccak256(bytes(signature)))
        return bytes4(keccak256(bytes(signature)));
        // ===== TODO END =====
    }

    /// @notice mapping(address => uint256) 声明在第 `slot` 个存储槽时，
    /// key 对应的值存放在 keccak256(abi.encode(key, slot))
    function mappingSlot(address key, uint256 slot) internal pure returns (bytes32) {
        // ===== TODO BEGIN =====
        // HINT: keccak256(abi.encode(key, slot))
        return keccak256(abi.encode(key, slot));
        // ===== TODO END =====
    }

    /// @notice CREATE2 地址 = keccak256(0xff ++ deployer ++ salt ++ keccak256(initCode)) 的后 20 字节
    /// Uniswap V2 的 pairFor() 就是用这个公式在链下/链上算出交易对地址，而不用查询 Factory
    function create2Address(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        // ===== TODO BEGIN =====
        // HINT: address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))))
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
        // ===== TODO END =====
    }
}
