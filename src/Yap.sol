// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./YapOracle.sol";

contract EnhancedKOLFutures is AccessControl {
    bytes32 public constant RISK_MANAGER_ROLE = keccak256("RISK_MANAGER_ROLE");

    IERC20 public immutable usdc;
    YapOracle public oracle;

    // Platform parameters
    uint256 public constant MAX_POSITION_SIZE = 10_000 * 1e6; // 10k USDC
    uint256 public constant MIN_POSITION_SIZE = 10 * 1e6; // 10 USDC
    uint256 public constant BASE_FEE_BPS = 10; // 0.1%
    uint256 public constant MAX_UTIL_RATIO = 8000; // 80%

    struct Position {
        address trader;
        uint256 kolId;
        uint256 entryRank;
        uint256 amount;
        bool isLong;
        uint256 openTimestamp;
        bool isSettled;
    }

    // Position tracking
    Position[] public positions;
    mapping(address => uint256[]) public userPositions;

    // Platform state
    uint256 public totalLongPositions;
    uint256 public totalShortPositions;
    uint256 public platformLiquidity;

    // Events
    event PositionOpened(
        uint256 indexed positionId,
        address indexed trader,
        uint256 kolId,
        uint256 amount,
        bool isLong,
        uint256 entryRank
    );

    event PositionSettled(
        uint256 indexed positionId,
        uint256 exitRank,
        uint256 pnlAmount,
        bool isProfit
    );

    constructor(address _usdc, address _oracle) {
        usdc = IERC20(_usdc);
        oracle = YapOracle(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function openPosition(uint256 kolId, uint256 amount, bool isLong) external {
        require(amount >= MIN_POSITION_SIZE, "Below min position size");
        require(amount <= MAX_POSITION_SIZE, "Exceeds max position size");

        // Get current KOL data
        (uint256 currentRank, , , bool isStale) = oracle.getKOLData(kolId);
        require(!isStale, "Stale oracle data");

        // Check platform liquidity and utilization
        require(_checkUtilization(amount, isLong), "Exceeds platform capacity");

        // Transfer USDC from user
        require(
            usdc.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        // Create position
        uint256 positionId = positions.length;
        positions.push(
            Position({
                trader: msg.sender,
                kolId: kolId,
                entryRank: currentRank,
                amount: amount,
                isLong: isLong,
                openTimestamp: block.timestamp,
                isSettled: false
            })
        );

        // Update state
        userPositions[msg.sender].push(positionId);
        if (isLong) {
            totalLongPositions += amount;
        } else {
            totalShortPositions += amount;
        }
        platformLiquidity += amount;

        emit PositionOpened(
            positionId,
            msg.sender,
            kolId,
            amount,
            isLong,
            currentRank
        );
    }

    function settlePosition(uint256 positionId) external {
        require(positionId < positions.length, "Invalid position ID");
        Position storage position = positions[positionId];
        require(!position.isSettled, "Position already settled");

        // Fetch final rank from oracle
        (uint256 finalRank, , , bool isStale) = oracle.getKOLData(
            position.kolId
        );
        require(!isStale, "Stale oracle data");

        // Calculate PnL
        (uint256 pnlAmount, bool isProfit) = calculatePnL(
            position.entryRank,
            finalRank,
            position.amount,
            position.isLong
        );

        // Update platform liquidity
        if (isProfit) {
            require(
                platformLiquidity >= pnlAmount,
                "Insufficient platform liquidity"
            );
            platformLiquidity -= pnlAmount;
        } else {
            platformLiquidity += pnlAmount;
        }

        // Mark position as settled
        position.isSettled = true;

        // Emit event
        emit PositionSettled(positionId, finalRank, pnlAmount, isProfit);

        // Transfer funds to trader (if profit) or deduct losses
        if (isProfit) {
            require(
                usdc.transfer(position.trader, position.amount + pnlAmount),
                "Transfer failed"
            );
        } else {
            require(
                usdc.transfer(position.trader, position.amount - pnlAmount),
                "Transfer failed"
            );
        }
    }

    function calculatePnL(
        uint256 entryRank,
        uint256 exitRank,
        uint256 amount,
        bool isLong
    ) public pure returns (uint256 pnlAmount, bool isProfit) {
        // Advanced PnL calculation using non-linear impact
        uint256 rankDiff;

        if (isLong) {
            // Special case: Rank 1 bonus
            if (entryRank == 1 && exitRank == 1) {
                pnlAmount = (amount * 10) / 10000; // 0.1% bonus
                isProfit = true;
                return (pnlAmount, isProfit); // Skip further calculations
            } else {
                isProfit = exitRank < entryRank;
                rankDiff = isProfit
                    ? entryRank - exitRank
                    : exitRank - entryRank;
            }
        } else {
            isProfit = exitRank > entryRank;
            rankDiff = isProfit ? exitRank - entryRank : entryRank - exitRank;
        }

        // Non-linear impact calculation
        // More impact for rank changes near the top
        uint256 impactMultiplier = calculateImpactMultiplier(
            isLong ? entryRank : exitRank
        );

        // Base PnL calculation
        uint256 basePnL = (amount * (rankDiff * impactMultiplier)) / 10000;

        // Apply diminishing returns for large rank changes
        uint256 finalPnL = applyDiminishingReturns(basePnL, rankDiff);

        return (finalPnL, isProfit);
    }

    function calculateImpactMultiplier(
        uint256 rank
    ) public pure returns (uint256) {
        if (rank <= 10) {
            return 200 - ((rank - 1) * 5);
        } else if (rank <= 30) {
            return 150 - ((rank - 11) * 2);
        } else if (rank <= 70) {
            return 100 - ((rank - 31) / 2);
        } else {
            return 75 - ((rank - 71) / 4);
        }
    }

    function applyDiminishingReturns(
        uint256 basePnL,
        uint256 rankDiff
    ) public pure returns (uint256) {
        // Apply diminishing returns for large rank changes
        if (rankDiff <= 5) {
            return basePnL;
        } else if (rankDiff <= 10) {
            return (basePnL * 80) / 100; // 80% of base PnL
        } else if (rankDiff <= 20) {
            return (basePnL * 60) / 100; // 60% of base PnL
        } else {
            return (basePnL * 40) / 100; // 40% of base PnL
        }
    }

    function _checkUtilization(
        uint256 amount,
        bool isLong
    ) internal view returns (bool) {
        uint256 newTotal = isLong
            ? totalLongPositions + amount
            : totalShortPositions + amount;

        return (newTotal * 10000) / (platformLiquidity + 1) <= MAX_UTIL_RATIO;
    }
}
