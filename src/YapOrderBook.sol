// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IYapEscrow} from "./interfaces/IYapEscrow.sol";
import {IYapOracle} from "./interfaces/IYapOracle.sol";

/**
 * @title yapfun
 * @dev An onchain orderbook for trading KOL mindshare positions using Kaito data
 */
contract YapFun is AccessControl {
    //error
    error YOB__INVALIDSIZE();
    error YOB__InvalidOrder();
    error YOB__DATA_EXPIRED();
    error YOB__INVALID_TRADER();
    error YOB__CallerIsNotTrader();
    error YOB__OrderYetToBeFilled();
    error YOB__Insufficient_Liquidity();

    // Order status
    enum OrderStatus {
        ACTIVE,
        FILLED,
        PARTIAL_FILLED,
        CANCELED
    }

    // Order structure
    struct Order {
        address trader;
        uint256 positionId;
        uint256 kolId; // ID of the Key Opinion Leader (KOL)
        bool isLong; // true = LONG, false = SHORT
        uint256 mindshareValue; // Mindshare metric value for matching
        uint256 quantity; // Amount of USDC/USDT to invest
        uint256 filledQuantity; // Amount already filled
        uint256 timestamp;
        OrderStatus status;
    }

    // Counters for order IDs
    uint256 private nextOrderId = 1;

    uint256 public immutable kolId;

    // Order storage - orderId => Order
    mapping(uint256 => Order) public orders;

    // Index orders by KOL and position type
    // isLong => mindshareValue => orderIds[]
    mapping(bool => mapping(uint256 => uint256[])) private orderIndex;

    // Track active orders count by KOL
    mapping(uint256 => uint256) public activeOrderCount;

    // USDC/USDT interface
    IERC20 public stablecoin;

    IYapEscrow public immutable escrow;
    IYapOracle public immutable oracle;

    // Fee configuration
    uint256 public feePercentage = 30; // 0.3% fee (basis points)
    address public feeCollector;

    // Events
    event OrderCreated(
        uint256 indexed orderId,
        address indexed trader,
        uint256 indexed kolId,
        bool isLong,
        uint256 mindshareValue,
        uint256 quantity
    );
    event OrderFilled(
        uint256 indexed orderId,
        uint256 filledQuantity,
        address counterpartyTrader
    );
    event OrderCanceled(uint256 indexed orderId, Order order);

    event PositionClosed(
        address user,
        address market,
        int256 pnl,
        uint256 positionId
    );

    /**
     * @dev Constructor
     * @param _stablecoin Address of the USDC/USDT contract
     * @param _feeCollector Address that collects trading fees
     */
    constructor(
        address _stablecoin,
        address _feeCollector,
        address _escrow,
        address yapOracle,
        uint256 _kolId
    ) {
        stablecoin = IERC20(_stablecoin);
        escrow = IYapEscrow(_escrow);
        oracle = IYapOracle(yapOracle);
        feeCollector = _feeCollector;
        kolId = _kolId;
    }

    /**
     * @dev Create a new order in the orderbook
     * @param _isLong Whether this is a LONG position (true) or SHORT (false)
     * @param _quantity Amount of stablecoin to invest
     */
    function createOrder(
        bool _isLong,
        uint256 _quantity
    ) external returns (uint256) {
        if (_quantity < 0) revert YOB__INVALIDSIZE();

        // Transfer stablecoin to contract
        escrow.fulfillOrder(_quantity, msg.sender, address(this));

        // Create the order
        uint256 orderId = nextOrderId++;
        uint256 _mindshareValue = _getOraclePrice(kolId);
        Order storage order = orders[orderId];
        order.trader = msg.sender;
        order.positionId = orderId;
        order.kolId = kolId;
        order.isLong = _isLong;
        order.mindshareValue = _mindshareValue;
        order.quantity = _quantity;
        order.filledQuantity = 0;
        order.timestamp = block.timestamp;
        order.status = OrderStatus.ACTIVE;

        // Index the order
        orderIndex[_isLong][_mindshareValue].push(orderId);
        activeOrderCount[kolId]++;

        emit OrderCreated(
            orderId,
            msg.sender,
            kolId,
            _isLong,
            _mindshareValue,
            _quantity
        );

        // Try to match the order immediately
        _matchOrder(orderId);

        return orderId;
    }

    /**
     * @dev Cancel an existing order
     * @param _orderId ID of the order to cancel
     */
    function cancelOrder(uint256 _orderId) external {
        Order storage order = orders[_orderId];
        if (order.trader != msg.sender) revert YOB__CallerIsNotTrader();
        if (
            order.status != OrderStatus.ACTIVE ||
            order.status != OrderStatus.PARTIAL_FILLED
        ) revert YOB__InvalidOrder();

        // Calculate refund amount
        uint256 refundAmount = order.quantity - order.filledQuantity;

        // Update order status
        order.status = OrderStatus.CANCELED;
        activeOrderCount[order.kolId]--;

        emit OrderCanceled(_orderId, order);

        // Refund remaining stablecoin
        if (refundAmount > 0) {
            escrow.settlePnL(msg.sender, refundAmount, address(this));
        }
    }

    /**
     * @dev Closes a position in the order book.
     * @param positionId The ID of the position to close.
     */
    function closePosition(
        uint256 positionId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Order storage pos = orders[positionId];
        if (msg.sender != pos.trader) revert YOB__INVALID_TRADER();
        if (pos.filledQuantity <= 0) revert YOB__OrderYetToBeFilled();

        uint256 currentPrice = _getOraclePrice(kolId);

        int256 pnl = _calculatePnL(pos, currentPrice);

        emit PositionClosed(msg.sender, address(this), pnl, positionId);

        delete orders[positionId];

        // Deduct losses from collateral or add profits
        _settlePnL(msg.sender, pnl, pos.filledQuantity);
    }

    /**
     * @dev Settles the profit or loss from a position.
     * @param trader The address of the trader.
     * @param pnl The profit or loss.
     * @param size The size of the position.
     */
    function _settlePnL(address trader, int256 pnl, uint256 size) internal {
        if (pnl > 0) {
            if (stablecoin.balanceOf(address(this)) < uint256(pnl))
                revert YOB__Insufficient_Liquidity();

            escrow.settlePnL(trader, size + uint256(pnl), address(this));
        } else {
            escrow.settlePnL(trader, size - uint256(-pnl), address(this));
        }
    }

    /**
     * @dev Calculates the profit or loss from a position.
     * @param pos The position to calculate the profit or loss for.
     * @param currentPrice The current price.
     * @return The profit or loss.
     */
    function _calculatePnL(
        Order memory pos,
        uint256 currentPrice
    ) internal pure returns (int256) {
        if (pos.isLong) {
            return
                int256(
                    (pos.filledQuantity * (currentPrice - pos.mindshareValue)) /
                        1e18
                );
        } else {
            return
                int256(
                    (pos.filledQuantity * (pos.mindshareValue - currentPrice)) /
                        1e18
                );
        }
    }

    /**
     * @dev Internal function to match a new order against existing orders
     * @param _orderId ID of the order to match
     */
    function _matchOrder(uint256 _orderId) internal {
        Order storage order = orders[_orderId];
        if (order.status != OrderStatus.ACTIVE) return;

        // Find matching orders with opposite position type
        bool oppositePosition = !order.isLong;

        uint256 totalFilled;

        // Get possible matching orders
        uint256[] storage matchingOrderIds = orderIndex[oppositePosition][
            order.mindshareValue
        ];

        // Match against available orders
        for (
            uint256 i = 0;
            i < matchingOrderIds.length &&
                order.filledQuantity < order.quantity;
            i++
        ) {
            uint256 matchId = matchingOrderIds[i];
            Order storage matchOrder = orders[matchId];

            // Skip if not active
            if (
                matchOrder.status != OrderStatus.ACTIVE &&
                matchOrder.status != OrderStatus.PARTIAL_FILLED
            ) continue;

            // Calculate fill amount
            uint256 matchAvailable = matchOrder.quantity -
                matchOrder.filledQuantity;
            uint256 orderRemaining = order.quantity - order.filledQuantity;
            uint256 fillAmount = matchAvailable < orderRemaining
                ? matchAvailable
                : orderRemaining;

            if (fillAmount > 0) {
                totalFilled += fillAmount;
                // Update both orders
                order.filledQuantity += fillAmount;
                matchOrder.filledQuantity += fillAmount;
                escrow.fulfillOrderWithLockedBalance(
                    fillAmount,
                    address(this),
                    matchOrder.trader
                );

                // Update order statuses
                if (matchOrder.filledQuantity == matchOrder.quantity) {
                    matchOrder.status = OrderStatus.FILLED;
                    activeOrderCount[matchOrder.kolId]--;
                } else {
                    matchOrder.status = OrderStatus.PARTIAL_FILLED;
                }

                emit OrderFilled(matchId, fillAmount, order.trader);
            }
        }

        uint256 feeAmount = (order.filledQuantity * feePercentage) / 10000;

        // Update final status of the order
        if (
            order.filledQuantity == order.quantity && order.filledQuantity > 0
        ) {
            emit OrderFilled(_orderId, order.filledQuantity, address(0));
            escrow.fulfillOrder(
                totalFilled + feeAmount,
                address(this),
                order.trader
            );
            order.status = OrderStatus.FILLED;
            activeOrderCount[order.kolId]--;
        } else if (order.filledQuantity > 0) {
            emit OrderFilled(_orderId, order.filledQuantity, address(0));
            escrow.fulfillOrder(
                totalFilled + feeAmount,
                address(this),
                order.trader
            );
            order.status = OrderStatus.PARTIAL_FILLED;
        } else if (order.filledQuantity == 0) {
            escrow.lockTheBalanceToFill(
                order.quantity,
                address(this),
                order.trader
            );
        }
    }

    /**
     * @dev Get order details
     * @param _orderId ID of the order to query
     */
    function getOrderDetails(
        uint256 _orderId
    )
        external
        view
        returns (
            address trader,
            uint256 _kolId,
            bool isLong,
            uint256 mindshareValue,
            uint256 quantity,
            uint256 filledQuantity,
            OrderStatus status
        )
    {
        Order storage order = orders[_orderId];
        return (
            order.trader,
            order.kolId,
            order.isLong,
            order.mindshareValue,
            order.quantity,
            order.filledQuantity,
            order.status
        );
    }

    /**
     * @dev Get count of active orders for a KOL
     */
    function getActiveOrderCount() external view returns (uint256) {
        return activeOrderCount[kolId];
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
     * @dev Update fee parameters (admin only function)
     * @param _newFeePercentage New fee in basis points (e.g., 30 = 0.3%)
     * @param _newFeeCollector New address to collect fees
     */
    function updateFeeParameters(
        uint256 _newFeePercentage,
        address _newFeeCollector
    ) external {
        // In production, add access control here
        require(_newFeePercentage <= 100, "Fee too high"); // Max 1%
        require(_newFeeCollector != address(0), "Invalid address");

        feePercentage = _newFeePercentage;
        feeCollector = _newFeeCollector;
    }
}

interface IERC20 {
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transfer(
        address recipient,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address account) external view returns (uint256);
}
