// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {DeployCourseToken} from "../../script/DeployCourseToken.s.sol";
import {CourseToken} from "ex/ch03/CourseToken.sol";

/// 部署脚本也是代码，也该有测试
contract DeployScriptTest is Test {
    function test_ScriptDeploysAndMints() public {
        DeployCourseToken script = new DeployCourseToken();
        CourseToken token = script.run();
        assertEq(token.totalSupply(), 1_000e18);
        assertEq(token.balanceOf(token.owner()), 1_000e18);
    }
}
