// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @notice 改写自 compound-finance/compound-protocol/contracts/JumpRateModelV2.sol
/// 原版按"每区块"计息；这里按"每秒"计息（Compound III、Aave 都是按秒）。
/// 所有利率都是 1e18 精度的定点数：1e18 = 100%。
///
///   借款利率
///      │                     ╱  jumpMultiplier（陡峭）
///      │                   ╱
///      │            ____╱    ← kink（拐点，如 80%）
///      │      ____╱          multiplier（平缓）
///      │ ___╱
///      │ baseRate
///      └──────────────────────── 资金利用率 U = borrows / (cash + borrows - reserves)
contract JumpRateModel {
    uint256 public constant BASE = 1e18;
    uint256 public constant SECONDS_PER_YEAR = 365 days;

    uint256 public immutable baseRatePerSecond;
    uint256 public immutable multiplierPerSecond;
    uint256 public immutable jumpMultiplierPerSecond;
    uint256 public immutable kink;

    /// @param baseRatePerYear       U = 0 时的年化借款利率，如 0.02e18 (2%)
    /// @param multiplierPerYear     拐点前的斜率，如 0.2e18：U 从 0 到 100% 利率增加 20%
    /// @param jumpMultiplierPerYear 拐点后的斜率，如 3e18
    /// @param kink_                 拐点利用率，如 0.8e18
    constructor(uint256 baseRatePerYear, uint256 multiplierPerYear, uint256 jumpMultiplierPerYear, uint256 kink_) {
        baseRatePerSecond = baseRatePerYear / SECONDS_PER_YEAR;
        multiplierPerSecond = multiplierPerYear / SECONDS_PER_YEAR;
        jumpMultiplierPerSecond = jumpMultiplierPerYear / SECONDS_PER_YEAR;
        kink = kink_;
    }

    function utilizationRate(uint256 cash, uint256 borrows, uint256 reserves) public pure returns (uint256) {
        if (borrows == 0) return 0;
        return borrows * BASE / (cash + borrows - reserves);
    }

    /// @notice 练习 1：分段线性的借款利率（每秒）
    function getBorrowRate(uint256 cash, uint256 borrows, uint256 reserves) public view returns (uint256) {
        uint256 util = utilizationRate(cash, borrows, reserves);
        // ===== TODO: 在这里写你的代码 =====
        // HINT: util <= kink:  util * multiplierPerSecond / BASE + baseRatePerSecond
        // HINT: 否则: normalRate = kink * multiplierPerSecond / BASE + baseRatePerSecond;
        // HINT:       return (util - kink) * jumpMultiplierPerSecond / BASE + normalRate;
        revert("TODO");
        // ===== TODO END =====
    }

    /// @notice 练习 2：存款利率 = 利用率 × 借款利率 × (1 - 储备金率)
    /// 直觉：借款人付的利息，扣掉协议抽成后，平摊给所有存款人
    function getSupplyRate(uint256 cash, uint256 borrows, uint256 reserves, uint256 reserveFactor)
        public
        view
        returns (uint256)
    {
        // ===== TODO: 在这里写你的代码 =====
        // HINT: rateToPool = getBorrowRate(...) * (BASE - reserveFactor) / BASE;
        // HINT: return utilizationRate(...) * rateToPool / BASE;
        revert("TODO");
        // ===== TODO END =====
    }
}
