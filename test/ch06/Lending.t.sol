// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../utils/MockERC20.sol";
import {JumpRateModel} from "ex/ch06/JumpRateModel.sol";
import {MiniLending, IPriceOracle} from "ex/ch06/MiniLending.sol";

/// 测试用预言机：价格可以随意设置（真实协议用 Chainlink，见讲义）
contract MockOracle is IPriceOracle {
    uint256 public price;

    function setPrice(uint256 p) external {
        price = p;
    }
}

contract JumpRateModelTest is Test {
    JumpRateModel model;
    uint256 constant YEAR = 365 days;

    function setUp() public {
        // 基础 2%，拐点前斜率 20%，拐点后斜率 300%，拐点 80%
        model = new JumpRateModel(0.02e18, 0.2e18, 3e18, 0.8e18);
    }

    /// 把"每秒利率"换算回年化，便于和直觉对照
    function _apr(uint256 cash, uint256 borrows) internal view returns (uint256) {
        return model.getBorrowRate(cash, borrows, 0) * YEAR;
    }

    function test_Utilization() public view {
        assertEq(model.utilizationRate(100, 0, 0), 0);
        assertEq(model.utilizationRate(50, 50, 0), 0.5e18);
        assertEq(model.utilizationRate(40, 50, 10), 0.625e18); // 储备金不算可借资金
    }

    function test_BorrowRateBelowKink() public view {
        assertApproxEqRel(_apr(100, 0), 0.02e18, 1e12); // U=0   -> 2%
        assertApproxEqRel(_apr(50, 50), 0.12e18, 1e12); // U=50% -> 2% + 0.5*20% = 12%
        assertApproxEqRel(_apr(20, 80), 0.18e18, 1e12); // U=80% -> 18%（拐点）
    }

    function test_BorrowRateAboveKink() public view {
        // U=90% -> 18% + (90%-80%) * 300% = 48%
        assertApproxEqRel(_apr(10, 90), 0.48e18, 1e12);
        // U=100% -> 18% + 20% * 300% = 78%
        assertApproxEqRel(_apr(0, 100), 0.78e18, 1e12);
    }

    function test_SupplyRate() public view {
        // U=50%，借款利率 12%，储备金率 10%：存款利率 = 0.5 * 12% * 0.9 = 5.4%
        uint256 apr = model.getSupplyRate(50, 50, 0, 0.1e18) * YEAR;
        assertApproxEqRel(apr, 0.054e18, 1e12);
    }

    function testFuzz_RateMonotonic(uint256 u1, uint256 u2) public view {
        u1 = bound(u1, 0, 1e18);
        u2 = bound(u2, u1, 1e18);
        // cash + borrows = 1e18，borrows = u
        assertLe(model.getBorrowRate(1e18 - u1, u1, 0), model.getBorrowRate(1e18 - u2, u2, 0));
    }
}

contract MiniLendingTest is Test {
    MockERC20 usdc;
    MockERC20 weth;
    MockOracle oracle;
    JumpRateModel model;
    MiniLending pool;

    address lender = makeAddr("lender");
    address borrower = makeAddr("borrower");
    address liquidator = makeAddr("liquidator");

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 18); // 简化：18 位小数
        weth = new MockERC20("Wrapped Ether", "WETH", 18);
        oracle = new MockOracle();
        oracle.setPrice(2000e18); // 1 WETH = 2000 USDC
        model = new JumpRateModel(0.02e18, 0.2e18, 3e18, 0.8e18);
        pool = new MiniLending(IERC20(address(usdc)), IERC20(address(weth)), model, oracle);

        // 存款人提供 10 万 USDC
        usdc.mint(lender, 100_000e18);
        vm.startPrank(lender);
        usdc.approve(address(pool), type(uint256).max);
        pool.supply(100_000e18);
        vm.stopPrank();

        // 借款人抵押 10 WETH（价值 2 万）
        weth.mint(borrower, 10e18);
        vm.startPrank(borrower);
        weth.approve(address(pool), type(uint256).max);
        usdc.approve(address(pool), type(uint256).max);
        pool.depositCollateral(10e18);
        vm.stopPrank();
    }

    function test_BorrowUpToLTV() public {
        assertEq(pool.maxBorrow(borrower), 15_000e18); // 20000 * 75%
        vm.prank(borrower);
        pool.borrow(15_000e18);
        assertEq(usdc.balanceOf(borrower), 15_000e18);

        vm.expectRevert(MiniLending.InsufficientCollateral.selector);
        vm.prank(borrower);
        pool.borrow(1);
    }

    function test_HealthFactor() public {
        assertEq(pool.healthFactor(borrower), type(uint256).max); // 无债务
        vm.prank(borrower);
        pool.borrow(10_000e18);
        // 20000 * 80% / 10000 = 1.6
        assertEq(pool.healthFactor(borrower), 1.6e18);
    }

    function test_InterestAccruesOverOneYear() public {
        vm.prank(borrower);
        pool.borrow(10_000e18); // U = 10%，年化 2% + 10%*20% = 4%

        vm.warp(block.timestamp + 365 days);
        pool.accrueInterest();

        uint256 debt = pool.borrowBalance(borrower);
        console.log("debt after 1 year:", debt / 1e18);
        assertApproxEqRel(debt, 10_400e18, 1e14); // ≈ 10400，误差 < 0.01%
        assertApproxEqRel(pool.totalReserves(), 40e18, 1e14); // 利息的 10% 进储备金
    }

    /// 更频繁地 accrue = 更多次复利 = 更多利息（而且下半年利用率更高、利率更高）
    function test_InterestCompoundsWithMoreAccruals() public {
        vm.prank(borrower);
        pool.borrow(10_000e18);

        vm.warp(block.timestamp + 365 days / 2);
        pool.accrueInterest();
        vm.warp(block.timestamp + 365 days / 2);
        pool.accrueInterest();

        assertGt(pool.borrowBalance(borrower), 10_404e18);
    }

    function test_LenderEarnsInterest() public {
        vm.prank(borrower);
        pool.borrow(10_000e18);
        vm.warp(block.timestamp + 365 days);
        pool.accrueInterest();

        // 份额价值 = (90000 现金 + 10400 债务 - 40 储备) / 100000 = 1.0036
        assertApproxEqRel(pool.exchangeRate(), 1.0036e18, 1e14);
        // 和存款利率公式吻合：U * 借款利率 * (1 - 10%) = 10% * 4% * 0.9 = 0.36%
    }

    function test_RepayAllAfterInterest() public {
        vm.prank(borrower);
        pool.borrow(10_000e18);
        vm.warp(block.timestamp + 30 days);

        usdc.mint(borrower, 1_000e18); // 补点钱付利息
        vm.prank(borrower);
        pool.repay(type(uint256).max); // 超额会被截断为全部债务
        assertEq(pool.borrowBalance(borrower), 0);
    }

    function test_CannotWithdrawCollateralBelowLTV() public {
        vm.startPrank(borrower);
        pool.borrow(15_000e18);
        vm.expectRevert(MiniLending.InsufficientCollateral.selector);
        pool.withdrawCollateral(1e18);
        vm.stopPrank();
    }

    function test_LiquidationAfterPriceDrop() public {
        vm.prank(borrower);
        pool.borrow(15_000e18);

        oracle.setPrice(1800e18); // ETH 跌 10%
        // HF = 10 * 1800 * 0.8 / 15000 = 0.96 < 1
        assertEq(pool.healthFactor(borrower), 0.96e18);

        usdc.mint(liquidator, 7_500e18);
        vm.startPrank(liquidator);
        usdc.approve(address(pool), type(uint256).max);
        uint256 seized = pool.liquidate(borrower, 7_500e18); // 50% close factor 上限
        vm.stopPrank();

        // 拿到 7500 * 1.05 / 1800 = 4.375 WETH，市值 7875，赚 375
        assertEq(seized, 4.375e18);
        assertEq(weth.balanceOf(liquidator), 4.375e18);
        assertEq(pool.borrowBalance(borrower), 7_500e18);
        assertGt(pool.healthFactor(borrower), 1e18); // 清算后恢复健康：5.625*1800*0.8/7500 = 1.08
    }

    function test_CannotLiquidateHealthyPosition() public {
        vm.prank(borrower);
        pool.borrow(10_000e18);
        vm.expectRevert(MiniLending.HealthyPosition.selector);
        vm.prank(liquidator);
        pool.liquidate(borrower, 1e18);
    }

    function test_CannotLiquidateMoreThanCloseFactor() public {
        vm.prank(borrower);
        pool.borrow(15_000e18);
        oracle.setPrice(1800e18);
        vm.expectRevert(MiniLending.TooMuchRepay.selector);
        vm.prank(liquidator);
        pool.liquidate(borrower, 7_501e18);
    }
}
