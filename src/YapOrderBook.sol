// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IYapOracle} from "./interfaces/IYapOracle.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IYapEscrow} from "./interfaces/IYapEscrow.sol";

/**
 * @title YapOrderBook
 * @dev This contract is responsible for managing the order book, liquidity pool, and positions within the Yap protocol.
 * It ensures the efficient matching of buy and sell orders, maintains a pool of liquidity providers, and tracks the positions of traders.
 */
contract YapOrderBook is AccessControl {
    using SafeERC20 for IERC20;

    //error
    error YOB__EXPIRED();
    error YOB__INVALIDSIZE();
    error YOB__DATA_EXPIRED();
    error YOB__INVALID_TRADER();
    error YOB__INVALIDORDERSIZE();
    error YOB__InsufficientUserBalance();

    // Immutables
    IERC20 public immutable usdc;
    IYapOracle public immutable oracle;
    IYapEscrow private immutable escrow;

    address public immutable factory;
    uint256 public immutable influencerId;

    // Constants
    uint256 public constant POOL_FEE = 500; // 5%
    uint256 public constant MATCHED_FEE = 100; // 1%
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

    event PositionClosed(
        address user,
        address market,
        int256 pnl,
        bytes32 positionId
    );

    /**
     * @dev Initializes the contract with the necessary parameters.
     * @param _influencerId The ID of the influencer.
     * @param _expiration The expiration time for orders.
     * @param _usdc The address of the USDC token.
     * @param admin The address of the admin.
     */
    constructor(
        uint256 _influencerId,
        uint256 _expiration,
        address _usdc,
        address _oracle,
        address admin,
        address _escrow
    ) {
        factory = msg.sender;
        influencerId = _influencerId;
        expiration = block.timestamp + _expiration;
        usdc = IERC20(_usdc);
        oracle = IYapOracle(_oracle);
        escrow = IYapEscrow(_escrow);

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // Core: Hybrid Order Matching
    /**
     * @dev Opens a new position in the order book.
     * @param size The size of the position.
     * @param isLong Whether the position is long or short.
     */
    function openPosition(uint256 size, bool isLong) external {
        if (size <= 0) revert YOB__INVALIDSIZE();
        if (block.timestamp > expiration) revert YOB__EXPIRED();

        if (escrow.userToBalance(msg.sender) < size)
            revert YOB__InsufficientUserBalance();
        uint256 entryPrice = _getOraclePrice(influencerId);
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

            escrow.fulfillOrder(poolUsed + poolFee, address(this), msg.sender);
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
            escrow.lockTheBalanceToFill(remaining, address(this), msg.sender);
        }

        totalLiquidity += fee;
    }

    /**
     * @dev Closes a position in the order book.
     * @param positionId The ID of the position to close.
     */
    function closePosition(
        bytes32 positionId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Position storage pos = positions[msg.sender][positionId];
        if (msg.sender != pos.trader) revert YOB__INVALID_TRADER();
        if (pos.size <= 0) revert YOB__INVALIDORDERSIZE();

        uint256 currentPrice = _getOraclePrice(influencerId);

        int256 pnl = _calculatePnL(pos, currentPrice);

        emit PositionClosed(msg.sender, address(this), pnl, positionId);

        // Remove position
        delete positions[msg.sender][positionId];

        // Deduct losses from collateral or add profits
        _settlePnL(msg.sender, pnl, pos.size);
    }

    // Unified Queue Matching
    /**
     * @dev Matches orders in the order book with a given size and price.
     * @param q The order queue to match with.
     * @param size The size of the match.
     * @param price The price of the match.
     * @param isLong Whether the match is for a long or short position.
     * @return matched The size of the match.
     */
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
            escrow.fulfillOrder(matchSize + fee, address(this), msg.sender);
            escrow.fulfillOrder(matchSize + fee, address(this), order.trader);

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
        // Create Position
        _createPosition(msg.sender, matched, isLong, price, q.head);

        return matched;
    }

    /**
     * @dev Adds an order to the order book.
     * @param q The order queue to add to.
     * @param trader The address of the trader.
     * @param size The size of the order.
     */
    function _addToQueue(
        OrderQueue storage q,
        address trader,
        uint256 size
    ) internal {
        q.orders[q.tail] = Order(trader, size);
        q.tail++;
    }

    /**
     * @dev Settles the profit or loss from a position.
     * @param trader The address of the trader.
     * @param pnl The profit or loss.
     * @param size The size of the position.
     */
    function _settlePnL(address trader, int256 pnl, uint256 size) internal {
        if (pnl > 0) {
            require(totalLiquidity >= uint256(pnl), "!liquidity");
            totalLiquidity -= uint256(pnl);
            escrow.settlePnL(trader, size + uint256(pnl), address(this));
        } else {
            totalLiquidity += uint256(-pnl);
            escrow.settlePnL(trader, size - uint256(-pnl), address(this));
        }
    }

    // Helpers
    /**
     * @dev Creates a new position in the order book.
     * @param trader The address of the trader.
     * @param size The size of the position.
     * @param isLong Whether the position is long or short.
     * @param price The price of the position.
     * @param head The head of the order queue.
     */
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

        emit PositionOpened(trader, size, isLong, price);
        positions[trader][positionId] = Position(trader, size, isLong, price);
    }

    /**
     * @dev Calculates the profit or loss from a position.
     * @param pos The position to calculate the profit or loss for.
     * @param currentPrice The current price.
     * @return The profit or loss.
     */
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

    /**
     * @dev Gets the current price from the oracle.
     * @return The current price.
     */
    function _getOraclePrice(
        uint256 _influencerId
    ) public view returns (uint256) {
        (, uint256 mindshareScore, , bool isStale) = oracle.getKOLData(
            _influencerId
        );
        if (isStale) revert YOB__DATA_EXPIRED();

        return (mindshareScore * 1e18); // Scale to 18 decimals
    }

    /**
     * @dev Adds liquidity to the liquidity pool.
     * @param amount The amount of liquidity to add.
     */
    function addLiquidity(
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        totalLiquidity += amount;
    }

    /**
     * @dev Returns the minimum of two numbers.
     * @param a The first number.
     * @param b The second number.
     * @return The minimum of the two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }
}
