// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UniswapV2Library} from "ex/ch05/UniswapV2Library.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
}

interface IUniswapV2Router02 {
    function getAmountsOut(uint256 amountIn, address[] calldata path) external view returns (uint256[] memory);
    function swapExactETHForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        returns (uint256[] memory amounts);
}

interface IAaveV3Pool {
    function getUserAccountData(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
        external;
}

/// 主网分叉测试：在本地复制一份以太坊主网状态，直接和真实的 Uniswap / Aave 交互。
/// 需要一个主网 RPC（Alchemy / Infura / 公共节点均可）：
///   export MAINNET_RPC_URL=https://...
///   forge test --match-path test/ch07/MainnetFork.t.sol -vv
/// 没设置 MAINNET_RPC_URL 时，这些测试会自动跳过。
contract MainnetForkTest is Test {
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address constant UNI_V2_ROUTER = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address constant USDC_WETH_PAIR = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    address constant AAVE_V3_POOL = 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2;

    bool forked;

    function setUp() public {
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return;
        vm.createSelectFork(rpc); // 可加第二个参数固定区块号，让结果可复现
        forked = true;
    }

    modifier onlyFork() {
        if (!forked) {
            vm.skip(true);
        }
        _;
    }

    /// 练习检查：你在第 5 章写的 getAmountOut，与主网 Router 的报价逐 wei 一致
    function test_OurLibraryMatchesMainnetRouter() public onlyFork {
        (uint112 r0, uint112 r1,) = IUniswapV2Pair(USDC_WETH_PAIR).getReserves();
        // token0 是地址更小的那个：USDC(0xA0..) < WETH(0xC0..)
        assertEq(IUniswapV2Pair(USDC_WETH_PAIR).token0(), USDC);

        uint256 ours = UniswapV2Library.getAmountOut(1 ether, r1, r0);

        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        uint256 theirs = IUniswapV2Router02(UNI_V2_ROUTER).getAmountsOut(1 ether, path)[1];

        console.log("1 WETH -> USDC (6 decimals):", ours);
        assertEq(ours, theirs);
    }

    /// 真实 swap：用 1 ETH 在 Uniswap V2 换 USDC
    function test_SwapOnMainnetFork() public onlyFork {
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        uint256[] memory amounts = IUniswapV2Router02(UNI_V2_ROUTER).swapExactETHForTokens{value: 1 ether}(
            0, path, address(this), block.timestamp
        );
        assertEq(IERC20(USDC).balanceOf(address(this)), amounts[1]);
        assertGt(amounts[1], 0);
    }

    /// 在真实 Aave V3 上：存 10 WETH，借 5000 USDC，看健康因子
    function test_AaveV3SupplyAndBorrow() public onlyFork {
        deal(WETH, address(this), 10 ether); // forge-std 的 deal 能直接改 ERC-20 余额
        IERC20(WETH).approve(AAVE_V3_POOL, 10 ether);
        IAaveV3Pool(AAVE_V3_POOL).supply(WETH, 10 ether, address(this), 0);
        IAaveV3Pool(AAVE_V3_POOL).borrow(USDC, 5_000e6, 2, 0, address(this)); // 2 = 浮动利率

        (uint256 col, uint256 debt,,, uint256 ltv, uint256 hf) =
            IAaveV3Pool(AAVE_V3_POOL).getUserAccountData(address(this));
        console.log("collateral (USD, 8 decimals):", col);
        console.log("debt       (USD, 8 decimals):", debt);
        console.log("ltv (bps):", ltv);
        console.log("health factor (1e18):", hf);
        assertEq(IERC20(USDC).balanceOf(address(this)), 5_000e6);
        assertGt(hf, 1e18);
    }

    receive() external payable {}
}
