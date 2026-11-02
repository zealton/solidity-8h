// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {JumpRateModel} from "./JumpRateModel.sol";

interface IPriceOracle {
    /// 1 单位抵押品值多少借款资产，1e18 精度
    function price() external view returns (uint256);
}

/// @notice 单市场借贷协议，把 Compound V2 和 Aave V3 最核心的机制放在 ~200 行里：
/// - 存款人：存入借款资产 (如 USDC)，获得份额，份额价值随利息增长 (Compound cToken 的 exchangeRate)
/// - 借款人：存入抵押品 (如 WETH)，按 LTV 借出 USDC (Aave 的 LTV / liquidationThreshold)
/// - 计息：全局 borrowIndex 随时间复利增长，每个借款人只记 (本金, 借款时的 index) (Compound 的 accrueInterest)
/// - 清算：健康因子 < 1 时，任何人可以替借款人还最多 50% 的债，并以 5% 折扣拿走抵押品
/// 简化：两种代币都按 18 位小数处理；没有多市场、没有 aToken/cToken 可转让。
contract MiniLending {
    using SafeERC20 for IERC20;

    uint256 public constant WAD = 1e18;
    uint256 public constant LTV = 0.75e18; // 最多借抵押品价值的 75%
    uint256 public constant LIQUIDATION_THRESHOLD = 0.8e18; // 债务超过抵押品价值 80% 即可被清算
    uint256 public constant CLOSE_FACTOR = 0.5e18; // 单次最多清算 50% 债务
    uint256 public constant LIQUIDATION_BONUS = 1.05e18; // 清算人拿到 105% 价值的抵押品
    uint256 public constant RESERVE_FACTOR = 0.1e18; // 利息的 10% 归协议

    IERC20 public immutable asset; // 可借资产，如 USDC
    IERC20 public immutable collateral; // 抵押品，如 WETH
    JumpRateModel public immutable rateModel;
    IPriceOracle public immutable oracle;

    // ---- 全局计息状态（Compound 命名）----
    uint256 public totalBorrows;
    uint256 public totalReserves;
    uint256 public borrowIndex = WAD;
    uint256 public accrualTimestamp;

    // ---- 存款份额 ----
    uint256 public totalShares;
    mapping(address => uint256) public sharesOf;

    // ---- 借款人 ----
    struct BorrowSnapshot {
        uint256 principal; // 上次变动后的债务
        uint256 interestIndex; // 上次变动时的 borrowIndex
    }

    mapping(address => BorrowSnapshot) public borrows;
    mapping(address => uint256) public collateralOf;

    error InsufficientCollateral();
    error InsufficientCash();
    error HealthyPosition();
    error TooMuchRepay();

    event AccrueInterest(uint256 interestAccumulated, uint256 borrowIndex, uint256 totalBorrows);
    event Liquidate(address indexed liquidator, address indexed borrower, uint256 repayAmount, uint256 seized);

    constructor(IERC20 asset_, IERC20 collateral_, JumpRateModel rateModel_, IPriceOracle oracle_) {
        asset = asset_;
        collateral = collateral_;
        rateModel = rateModel_;
        oracle = oracle_;
        accrualTimestamp = block.timestamp;
    }

    // ================= 计息 =================

    function getCash() public view returns (uint256) {
        return asset.balanceOf(address(this));
    }

    /// @notice 练习 1：Compound 的 accrueInterest()，每次与协议交互前都要调用
    function accrueInterest() public {
        uint256 elapsed = block.timestamp - accrualTimestamp;
        if (elapsed == 0) return;
        // ===== TODO BEGIN =====
        // HINT: borrowRate = rateModel.getBorrowRate(getCash(), totalBorrows, totalReserves);
        // HINT: simpleInterestFactor = borrowRate * elapsed;              // 这段时间的单利，1e18 精度
        // HINT: interestAccumulated = simpleInterestFactor * totalBorrows / WAD;
        // HINT: totalBorrows += interestAccumulated;
        // HINT: totalReserves += interestAccumulated * RESERVE_FACTOR / WAD;
        // HINT: borrowIndex += simpleInterestFactor * borrowIndex / WAD;  // index 复利增长
        // HINT: accrualTimestamp = block.timestamp; 最后 emit AccrueInterest(...)
        uint256 borrowRate = rateModel.getBorrowRate(getCash(), totalBorrows, totalReserves);
        uint256 simpleInterestFactor = borrowRate * elapsed;
        uint256 interestAccumulated = simpleInterestFactor * totalBorrows / WAD;

        totalBorrows += interestAccumulated;
        totalReserves += interestAccumulated * RESERVE_FACTOR / WAD;
        borrowIndex += simpleInterestFactor * borrowIndex / WAD;
        accrualTimestamp = block.timestamp;

        emit AccrueInterest(interestAccumulated, borrowIndex, totalBorrows);
        // ===== TODO END =====
    }

    /// 借款人当前债务 = 本金 × 当前 index / 借款时 index
    function borrowBalance(address user) public view returns (uint256) {
        BorrowSnapshot memory s = borrows[user];
        if (s.principal == 0) return 0;
        return s.principal * borrowIndex / s.interestIndex;
    }

    // ================= 存款人 =================

    /// 1 份额 = 多少资产。借款人付的利息让它持续上涨
    function exchangeRate() public view returns (uint256) {
        if (totalShares == 0) return WAD;
        return (getCash() + totalBorrows - totalReserves) * WAD / totalShares;
    }

    function supply(uint256 amount) external returns (uint256 shares) {
        accrueInterest();
        shares = amount * WAD / exchangeRate();
        totalShares += shares;
        sharesOf[msg.sender] += shares;
        asset.safeTransferFrom(msg.sender, address(this), amount);
    }

    function redeem(uint256 shares) external returns (uint256 amount) {
        accrueInterest();
        amount = shares * exchangeRate() / WAD;
        if (amount > getCash()) revert InsufficientCash();
        sharesOf[msg.sender] -= shares;
        totalShares -= shares;
        asset.safeTransfer(msg.sender, amount);
    }

    // ================= 借款人 =================

    function depositCollateral(uint256 amount) external {
        collateralOf[msg.sender] += amount;
        collateral.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdrawCollateral(uint256 amount) external {
        accrueInterest();
        collateralOf[msg.sender] -= amount;
        if (borrowBalance(msg.sender) > maxBorrow(msg.sender)) revert InsufficientCollateral();
        collateral.safeTransfer(msg.sender, amount);
    }

    function collateralValue(address user) public view returns (uint256) {
        return collateralOf[user] * oracle.price() / WAD;
    }

    function maxBorrow(address user) public view returns (uint256) {
        return collateralValue(user) * LTV / WAD;
    }

    /// @notice 练习 2：Aave 的健康因子 HF = 抵押品价值 × 清算阈值 / 债务
    /// HF >= 1e18 安全；< 1e18 可被清算；没有债务时返回 type(uint256).max
    function healthFactor(address user) public view returns (uint256) {
        // ===== TODO BEGIN =====
        // HINT: uint256 debt = borrowBalance(user); if (debt == 0) return type(uint256).max;
        // HINT: return collateralValue(user) * LIQUIDATION_THRESHOLD / debt;
        uint256 debt = borrowBalance(user);
        if (debt == 0) return type(uint256).max;
        return collateralValue(user) * LIQUIDATION_THRESHOLD / debt;
        // ===== TODO END =====
    }

    function borrow(uint256 amount) external {
        accrueInterest();
        uint256 newDebt = borrowBalance(msg.sender) + amount;
        if (newDebt > maxBorrow(msg.sender)) revert InsufficientCollateral();
        if (amount > getCash()) revert InsufficientCash();

        borrows[msg.sender] = BorrowSnapshot(newDebt, borrowIndex);
        totalBorrows += amount;
        asset.safeTransfer(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        accrueInterest();
        _repay(msg.sender, msg.sender, amount);
    }

    function _repay(address payer, address borrower, uint256 amount) internal {
        uint256 debt = borrowBalance(borrower);
        if (amount > debt) amount = debt;
        borrows[borrower] = BorrowSnapshot(debt - amount, borrowIndex);
        totalBorrows = totalBorrows > amount ? totalBorrows - amount : 0;
        asset.safeTransferFrom(payer, address(this), amount);
    }

    // ================= 清算 =================

    /// 清算人替 borrower 还 repayAmount 的债，换取 repayAmount × 105% 价值的抵押品
    function liquidate(address borrower, uint256 repayAmount) external returns (uint256 seized) {
        accrueInterest();
        if (healthFactor(borrower) >= WAD) revert HealthyPosition();
        if (repayAmount > borrowBalance(borrower) * CLOSE_FACTOR / WAD) revert TooMuchRepay();

        seized = repayAmount * LIQUIDATION_BONUS / oracle.price();
        if (seized > collateralOf[borrower]) seized = collateralOf[borrower];

        _repay(msg.sender, borrower, repayAmount);
        collateralOf[borrower] -= seized;
        collateral.safeTransfer(msg.sender, seized);
        emit Liquidate(msg.sender, borrower, repayAmount, seized);
    }
}
