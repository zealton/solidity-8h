// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {CourseToken} from "ex/ch03/CourseToken.sol";

/// 用法（本地链）：
///   anvil                                    # 另开一个终端，启动本地链
///   forge script script/DeployCourseToken.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
/// 不加 --broadcast 就只做本地模拟，不发交易。
/// 部署到测试网时：export PRIVATE_KEY=0x...（千万别把私钥提交到 git）
contract DeployCourseToken is Script {
    // anvil 默认第 0 个账户的私钥，公开的测试私钥，只能用于本地链
    uint256 constant ANVIL_KEY_0 = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

    function run() external returns (CourseToken token) {
        uint256 pk = vm.envOr("PRIVATE_KEY", ANVIL_KEY_0);
        address deployer = vm.addr(pk);

        vm.startBroadcast(pk); // 之后的每个外部调用/部署都会变成一笔由 deployer 签名的交易
        token = new CourseToken(deployer);
        token.mint(deployer, 1_000e18);
        vm.stopBroadcast();

        console.log("CourseToken deployed at:", address(token));
        console.log("owner:", token.owner());
    }
}
