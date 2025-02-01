// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract YapOrderBook is AccessControl {
    using SafeERC20 for IERC20;

    //error
    error YOB__EXPIRED();
    error YOB__INVALIDSIZE();
    error YOB__INVALID_TRADER();
    error YOB__INVALIDORDERSIZE();

    // Immutables
    address public immutable factory;
    uint256 public immutable influencerId;
    IERC20 public immutable usdc;
    AggregatorV3Interface public mindshareFeed;

    // Constants
    uint256 public constant POOL_FEE = 500; // 5%
    uint256 public constant MATCHED_FEE = 100; // 1%
    address public insuranceFund;
    uint256 public expiration;

    // Order Book
    struct Order {
        address trader;
        uint256 size;
    }
    struct OrderQueue {
        uint256 head;
        uint256 tail;
        mapping(uint256 => Order) orders;
    }
    OrderQueue public longQueue;
    OrderQueue public shortQueue;

    // Liquidity Pool
    uint256 public totalLiquidity;

    // Positions
    struct Position {
        address trader;
        uint256 size;
        bool isLong;
        uint256 entryPrice;
    }
    mapping(address => mapping(bytes32 => Position)) public positions;

    event PositionOpened(
        address indexed trader,
        uint256 size,
        bool isLong,
        uint256 entryPrice
    );
    event OrderMatched(
        address indexed long,
        address indexed short,
        uint256 size,
        uint256 price
    );

    constructor(
        uint256 _influencerId,
        uint256 _expiration,
        address _usdc,
        address _mindshareFeed,
        address _insuranceFund,
        address admin
    ) {
        factory = msg.sender;
        influencerId = _influencerId;
        expiration = _expiration;
        usdc = IERC20(_usdc);
        mindshareFeed = AggregatorV3Interface(_mindshareFeed);
        insuranceFund = _insuranceFund;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // Core: Hybrid Order Matching
    function openPosition(uint256 size, bool isLong) external {
        if (size <= 0) revert YOB__INVALIDSIZE();
        if (block.timestamp > expiration) revert YOB__EXPIRED();
        uint256 entryPrice = _getOraclePrice();
        uint256 remaining = size;

        // 1. Match with Order Book
        uint256 matched = isLong
            ? _matchWithQueue(shortQueue, size, entryPrice, true)
            : _matchWithQueue(longQueue, size, entryPrice, false);

        uint256 fee = (matched * MATCHED_FEE) / 10000;

        remaining -= matched;

        // 2. Handle Residual with Pool
        if (remaining > 0 && totalLiquidity > 0) {
            uint256 poolUsed = min(remaining, totalLiquidity);
            uint256 poolFee = (poolUsed * POOL_FEE) / 10000;
            totalLiquidity -= poolUsed;
            usdc.safeTransferFrom(
                msg.sender,
                address(this),
                poolUsed + poolFee
            );
            _createPosition(
                msg.sender,
                poolUsed,
                isLong,
                entryPrice,
                isLong ? shortQueue.head : longQueue.head
            );
            remaining -= poolUsed;
        }

        // 3. Add Residual to Order Book
        if (remaining > 0) {
            _createPosition(
                msg.sender,
                remaining,
                isLong,
                entryPrice,
                isLong ? shortQueue.head : longQueue.head
            );
            _addToQueue(isLong ? longQueue : shortQueue, msg.sender, remaining);
        }

        totalLiquidity += fee;
    }

    // Add to contract
    function closePosition(bytes32 positionId) external {
        Position storage pos = positions[msg.sender][positionId];
        if (msg.sender != pos.trader) revert YOB__INVALID_TRADER();
        if (pos.size <= 0) revert YOB__INVALIDORDERSIZE();

        uint256 currentPrice = _getOraclePrice();

        int256 pnl = _calculatePnL(pos, currentPrice);

        // Remove position
        delete positions[msg.sender][positionId];

        // Deduct losses from collateral or add profits
        _settlePnL(msg.sender, pnl, pos.size);
    }

    // Unified Queue Matching
    function _matchWithQueue(
        OrderQueue storage q,
        uint256 size,
        uint256 price,
        bool isLong
    ) internal returns (uint256 matched) {
        while (size > 0 && q.head < q.tail) {
            Order storage order = q.orders[q.head];
            uint256 matchSize = min(size, order.size);

            uint256 fee = (matched * MATCHED_FEE) / 10000;

            usdc.safeTransferFrom(msg.sender, address(this), matchSize + fee);
            usdc.safeTransferFrom(order.trader, address(this), matchSize + fee);

            // Create Position
            _createPosition(msg.sender, matchSize, isLong, price, q.head);

            emit OrderMatched(msg.sender, order.trader, matchSize, price);

            // Update State
            size -= matchSize;
            order.size -= matchSize;
            matched += matchSize;

            if (order.size == 0) {
                delete q.orders[q.head];
                q.head++;
            }
        }

        return matched;
    }

    function _addToQueue(
        OrderQueue storage q,
        address trader,
        uint256 size
    ) internal {
        q.orders[q.tail] = Order(trader, size);
        q.tail++;
    }

    function _calculatePnL(
        Position memory pos,
        uint256 currentPrice
    ) internal pure returns (int256) {
        if (pos.isLong) {
            return int256((pos.size * (currentPrice - pos.entryPrice)) / 1e18);
        } else {
            return int256((pos.size * (pos.entryPrice - currentPrice)) / 1e18);
        }
    }

    function _settlePnL(address trader, int256 pnl, uint256 size) internal {
        if (pnl > 0) {
            require(totalLiquidity >= uint256(pnl), "!liquidity");
            totalLiquidity -= uint256(pnl);
            usdc.safeTransfer(trader, size + uint256(pnl));
        } else {
            totalLiquidity += uint256(-pnl);
            usdc.safeTransfer(trader, size - uint256(-pnl));
        }
    }

    // Helpers
    function _createPosition(
        address trader,
        uint256 size,
        bool isLong,
        uint256 price,
        uint256 head
    ) internal {
        bytes32 positionId = keccak256(
            abi.encodePacked(trader, block.timestamp, head, size, isLong, price)
        );

        positions[trader][positionId] = Position(trader, size, isLong, price);
        emit PositionOpened(trader, size, isLong, price);
    }

    function _getOraclePrice() public pure returns (uint256) {
        // (, int256 answer, , uint256 updatedAt, ) = mindshareFeed
        //     .latestRoundData();
        // require(block.timestamp - updatedAt < 1 hours, "Stale");
        return 37000000000000000; // Scale to 18 decimals
    }

    function addLiquidity(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        totalLiquidity += amount;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
