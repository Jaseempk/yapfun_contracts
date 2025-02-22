// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IYapEscrow} from "./interfaces/IYapEscrow.sol";
import {IYapOracle} from "./interfaces/IYapOracle.sol";

/**
 * @title yapfun
 * @dev An onchain orderbook for trading KOL mindshare positions using Kaito data
 */
contract YapOrderBook is AccessControl {
    //error
    error YOB__INVALIDSIZE();
    error YOB__InvalidOrder();
    error YOB__DATA_EXPIRED();
    error YOB__INVALID_TRADER();
    error YOB__InvalidPosition();
    error YOB__CallerIsNotTrader();
    error YOB__OrderYetToBeFilled();
    error YOB__MindshareArrayEmpty();
    error YOB__CantResetActiveMarket();
    error YOB__CantCloseBeforeExpiry();
    error YOB__Insufficient_Liquidity();
    error YOB__WithdrawalAmountTooHigh();

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

    // KOL identifier
    uint256 private immutable kolId;

    // Market expiry timestamp
    uint256 public expiryDuration;

    // Total trading volume
    uint256 public marketVolume;

    uint256 public totalFeeCollected;

    // Order storage - orderId => Order
    mapping(uint256 => Order) public orders;

    // Index orders by KOL and position type
    // isLong => mindshareValue => orderIds[]
    mapping(bool => mapping(uint256 => uint256[])) private orderIndex;

    // Track active orders count by KOL
    mapping(uint256 => uint256) public activeOrderCount;

    // USDC/USDT interface
    IERC20 public stablecoin;

    // Interface for the escrow contract that handles funds
    IYapEscrow public immutable escrow;

    // Interface for the oracle contract that provides KOL data
    IYapOracle public immutable oracle;

    // Fee configuration
    uint256 public feePercentage = 30; // 0.3% fee (basis points)
    address public feeCollector;

    //constants
    uint32 public constant MARKET_DURATION = 3 days;

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

    event MarketReset(uint256 timestamp);

    event FeeWithdrawalInitiated(address caller, uint256 amountWithdrawn);

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
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stablecoin = IERC20(_stablecoin);
        escrow = IYapEscrow(_escrow);
        oracle = IYapOracle(yapOracle);
        feeCollector = _feeCollector;
        kolId = _kolId;
        expiryDuration = block.timestamp + MARKET_DURATION;
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
        if (_quantity <= 0) revert YOB__INVALIDSIZE();

        // Create the order
        uint256 orderId = nextOrderId++;
        uint256 _mindshareValue = _getOraclePrice();
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

        marketVolume += _quantity;

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
            order.status != OrderStatus.ACTIVE &&
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
            escrow.unlockBalanceUponExpiry(
                refundAmount,
                address(this),
                order.trader
            );
        }
    }

    /**
     * @dev Closes a position in the order book.
     * @param positionId The ID of the position to close.
     */
    function closePosition(
        uint256 positionId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        Order memory pos = orders[positionId];
        // if (msg.sender != pos.trader) revert YOB__INVALID_TRADER();
        if (block.timestamp < expiryDuration)
            revert YOB__CantCloseBeforeExpiry();
        if (pos.trader == address(0)) revert YOB__InvalidPosition();
        if (pos.filledQuantity == 0) {
            emit PositionClosed(msg.sender, address(this), 0, positionId);
            _removeFromOrderIndex(positionId, pos.isLong, pos.mindshareValue);
            escrow.unlockBalanceUponExpiry(
                pos.quantity,
                address(this),
                pos.trader
            );

            delete orders[positionId];
        } else {
            if ((pos.quantity - pos.filledQuantity) != 0) {
                escrow.unlockBalanceUponExpiry(
                    pos.quantity - pos.filledQuantity,
                    address(this),
                    pos.trader
                );
            }
            uint256 currentPrice = _getOraclePrice();

            int256 pnl = _calculatePnL(pos, currentPrice);

            uint256 feeAmount = (pos.filledQuantity * feePercentage) / 10000;

            totalFeeCollected += feeAmount;

            emit PositionClosed(msg.sender, address(this), pnl, positionId);

            _removeFromOrderIndex(positionId, pos.isLong, pos.mindshareValue);

            delete orders[positionId];

            // Deduct losses from collateral or add profits
            _settlePnL(msg.sender, pnl, pos.filledQuantity, feeAmount);
        }
    }

    /// @notice Resets market state by clearing order indices for specified mindshares
    /// @dev Can only be called by admin after market expiry
    /// @param mindshares Array of mindshare IDs to reset orders for
    /// @custom:throws YOB__CantResetActiveMarket if market has not expired yet
    function resetMarket(
        uint256[] calldata mindshares
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        if (mindshares.length == 0) revert YOB__MindshareArrayEmpty();
        if (block.timestamp < expiryDuration)
            revert YOB__CantResetActiveMarket();

        emit MarketReset(block.timestamp);
        for (uint i = 0; i < mindshares.length; i++) {
            delete orderIndex[true][mindshares[i]];
            delete orderIndex[false][mindshares[i]];
        }
        marketVolume = 1;
        expiryDuration = block.timestamp + MARKET_DURATION;
    }

    /**
     * @dev Settles the profit or loss from a position.
     * @param trader The address of the trader.
     * @param pnl The profit or loss.
     * @param size The size of the position.
     */
    function _settlePnL(
        address trader,
        int256 pnl,
        uint256 size,
        uint256 fee
    ) internal {
        if (pnl > 0) {
            if (stablecoin.balanceOf(address(this)) < uint256(pnl))
                revert YOB__Insufficient_Liquidity();

            escrow.settlePnL(
                trader,
                (size + uint256(pnl)) - fee,
                address(this)
            );
        } else {
            escrow.settlePnL(
                trader,
                (size - uint256(-pnl)) - fee,
                address(this)
            );
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

        // Update final status of the order
        if (order.filledQuantity == order.quantity) {
            order.status = OrderStatus.FILLED;
            activeOrderCount[order.kolId]--;

            emit OrderFilled(_orderId, order.filledQuantity, address(0));

            escrow.fulfillOrder(totalFilled, address(this), order.trader);
        } else if (order.filledQuantity > 0) {
            emit OrderFilled(_orderId, order.filledQuantity, address(0));

            escrow.fulfillOrder(totalFilled, address(this), order.trader);

            escrow.lockTheBalanceToFill(
                order.quantity - totalFilled,
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
     * @dev Removes an order ID from the orderIndex mapping
     * @param orderId Order ID to remove
     * @param isLong Position type
     * @param mindshareValue Mindshare value
     */
    function _removeFromOrderIndex(
        uint256 orderId,
        bool isLong,
        uint256 mindshareValue
    ) internal {
        uint256[] storage orderList = orderIndex[isLong][mindshareValue];

        // Find the index of the order ID in the array
        for (uint256 i = 0; i < orderList.length; i++) {
            if (orderList[i] == orderId) {
                // Replace with the last element and pop (gas efficient way to remove from array)
                if (i != orderList.length - 1) {
                    orderList[i] = orderList[orderList.length - 1];
                }

                // Update active order count if needed
                if (
                    orders[orderId].status == OrderStatus.ACTIVE ||
                    orders[orderId].status == OrderStatus.PARTIAL_FILLED
                ) {
                    activeOrderCount[kolId]--;
                }

                break;
            }
        }
    }

    /// @notice Allows admin to withdraw collected trading fees
    /// @param amountToWithdraw The amount of stablecoin fee to withdraw
    /// @dev Only callable by admin role
    function withdrawFee(
        uint256 amountToWithdraw
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amountToWithdraw > totalFeeCollected)
            revert YOB__WithdrawalAmountTooHigh();
        amountToWithdraw -= totalFeeCollected;

        emit FeeWithdrawalInitiated(msg.sender, amountToWithdraw);

        stablecoin.transferFrom(address(this), msg.sender, amountToWithdraw);
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
    function _getOraclePrice() public view returns (uint256) {
        (, uint256 mindshareScore, , bool isStale) = oracle.getKOLData(kolId);
        if (isStale) revert YOB__DATA_EXPIRED();

        return (mindshareScore * 1e18); // Scale to 18 decimals
    }

    /// @notice Get the number of orders for a specific mindshare position
    /// @param isLong Boolean indicating if orders are for long (true) or short (false) positions
    /// @param mindshare The mindshare ID to check orders for
    /// @return uint256 Number of orders for the specified mindshare and direction
    function getOrderCountForMindshare(
        bool isLong,
        uint256 mindshare
    ) public view returns (uint256) {
        return orderIndex[isLong][mindshare].length;
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
