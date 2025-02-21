//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {YapOrderBook} from "src/YapOrderBook.sol";
import {console} from "forge-std/console.sol";
import {YapEscrow} from "../../src/YapEscrow.sol";
import {YapOrderBookFactory} from "../../src/YapOrderBookFactory.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {YapOracle} from "../../src/YapOracle.sol";

contract YapOrderBookTest is Test {
    using LibRLP for address;
    YapOrderBook yap;
    YapEscrow escrow;
    YapOrderBookFactory factory;
    YapOracle oracle;
    IERC20 usdc;
    address constant FEED = address(0xdead);
    address constant INSURANCE = address(0xbeef);

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address admin = makeAddr("admin");
    address _escrow = makeAddr("factory");

    function setUp() public {
        usdc = IERC20(0x081827b8C3Aa05287b5aA2bC3051fbE638F33152);
        deal(address(usdc), alice, 1000e18);
        deal(address(usdc), bob, 1000e18);
        deal(address(usdc), charlie, 1000e18);
        YapEscrow yapEscrowComputed = YapEscrow(
            address(this).computeAddress(2)
        );

        factory = new YapOrderBookFactory(address(yapEscrowComputed));

        escrow = new YapEscrow(address(usdc), address(factory));
        assertEq(address(yapEscrowComputed), address(escrow));
        address _yap = factory.initialiseMarket(
            1, // influencerId
            FEED
        );

        yap = YapOrderBook(_yap);
    }

    function test_fullOrderBookMatch() public {
        // Alice opens short position
        vm.startPrank(alice);
        usdc.approve(address(escrow), 120e18);
        escrow.depositUserFund(120e18);

        yap.createOrder(false, 100e18);
        vm.stopPrank();

        // Bob matches with long
        vm.startPrank(bob);
        usdc.approve(address(escrow), 130e18);
        escrow.depositUserFund(130e18);
        yap.createOrder(true, 100e18);

        // (uint256 head, ) = yap.longQueue();
        vm.stopPrank();

        // Verify positions
        uint256 alicePosId = 1;

        uint256 bobPosId = 2;

        (, , , , , uint256 size, , , ) = yap.orders(alicePosId);
        (, , , , , uint256 _size, uint256 filledQty, , ) = yap.orders(bobPosId);
        uint256 fee = (filledQty * 30) / 10000;
        assertEq(size, 100e18);

        assertEq(_size, 100e18);
        assertEq(usdc.balanceOf(address(yap)), 200e18 + fee);
    }

    function test_partialMatch_withPool() public {
        // Seed liquidity pool
        vm.startPrank(charlie);
        usdc.approve(address(escrow), 50e18);
        escrow.depositUserFund(50e18);
        yap.createOrder(true, 50e18); // Adds to pool

        vm.stopPrank();

        // Alice opens large short
        vm.startPrank(alice);
        usdc.approve(address(escrow), 103e18);
        escrow.depositUserFund(103e18);
        yap.createOrder(false, 100e18);
        vm.stopPrank();

        // // Verify pool usage
        // assertEq(yap.totalLiquidity(), 50e18 * 0.01); // 1% fee on pool usage
        // (, uint256 tail) = yap.longQueue(); // Destructure the tuple
        // assertEq(tail, 1); // Residual should be in queue
    }

    function test_positionProfit_andLoss() public {
        // Alice opens long
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18);
        // (uint256 head, ) = yap.shortQueue();
        yap.createOrder(true, 100e18);
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(escrow), 102e18);
        escrow.depositUserFund(102e18);
        yap.createOrder(false, 100e18);
        vm.stopPrank();

        // Verify positions
        uint256 alicePosId = 1;

        // Simulate price increase
        uint256 newPrice = 4e18; // 40% increase from 3.7e18
        vm.mockCall(
            address(yap),
            abi.encodeWithSelector(YapOrderBook._getOraclePrice.selector),
            abi.encode(newPrice)
        );

        skip(7 days);
        vm.prank(address(factory));
        // Close position with profit
        yap.closePosition(alicePosId);
        assertEq(yap._getOraclePrice(), newPrice);

        console.log("mocked price: ", yap._getOraclePrice());

        // Calculate expected PnL: (4 - 3.7) * 100e18 / 1e18 = 30e18
        uint256 expectedBalance = 1000e18 - 100e18 + 100e18 + 30e18;
        assertEq(escrow.getUserBalance(alice), expectedBalance);
    }

    function test_orderCreation() public {
        // Add multiple orders
        for (uint256 i = 0; i < 3; i++) {
            vm.startPrank(alice);
            usdc.approve(address(escrow), 120e18);
            escrow.depositUserFund(120e18);
            yap.createOrder(true, 100e18);
            vm.stopPrank();
        }

        // Process orders
        vm.startPrank(bob);
        usdc.approve(address(escrow), 320e18);
        escrow.depositUserFund(320e18);
        yap.createOrder(false, 300e18);
        vm.stopPrank();
    }

    function test_closingOrder_before_expiration() public {
        test_orderCreation();
        // Verify positions
        uint256 alicePosId = 1;

        // Attempt to open position
        vm.startPrank(address(factory));
        vm.expectRevert(YapOrderBook.YOB__CantCloseBeforeExpiry.selector);
        yap.closePosition(alicePosId);
    }

    function test_zeroSize_position() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18);
        vm.expectRevert(YapOrderBook.YOB__INVALIDSIZE.selector);
        yap.createOrder(true, 0);
        vm.stopPrank();
    }

    function test_CancelOrder_Success() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        yap.createOrder(true, 50e18); // Create LONG order
        uint256 orderId = 1;
        yap.cancelOrder(orderId); // Cancel the order
        vm.stopPrank();

        // Validate cancellation
        (, , , , , , , , YapOrderBook.OrderStatus status) = yap.orders(orderId);
        assertEq(uint8(status), uint8(YapOrderBook.OrderStatus.CANCELED));
    }

    function test_CancelOrder_NotOwner() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        uint256 orderId = yap.createOrder(true, 50e18); // Create LONG order
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(YapOrderBook.YOB__CallerIsNotTrader.selector);
        yap.cancelOrder(orderId); // Bob tries to cancel Alice's order
        vm.stopPrank();
    }

    function test_MatchOrders_Success() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        uint256 orderIdAlice = yap.createOrder(true, 50e18); // Alice creates LONG order
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        uint256 orderIdBob = yap.createOrder(false, 50e18); // Bob creates SHORT order
        vm.stopPrank();

        // Validate matching
        (, , , , , , , , YapOrderBook.OrderStatus aliceStatus) = yap.orders(
            orderIdAlice
        );
        (, , , , , , , , YapOrderBook.OrderStatus bobStatus) = yap.orders(
            orderIdBob
        );
        assertEq(uint8(aliceStatus), uint8(YapOrderBook.OrderStatus.FILLED));
        assertEq(uint8(bobStatus), uint8(YapOrderBook.OrderStatus.FILLED));
    }

    function test_MatchOrders_PartialFill() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        uint256 orderIdAlice = yap.createOrder(true, 50e18); // Alice creates LONG order
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        uint256 orderIdBob = yap.createOrder(false, 30e18); // Bob creates SHORT order (partial fill)
        vm.stopPrank();

        // // Validate partial fill
        (, , , , , , uint256 filledQuantity, , ) = yap.orders(orderIdAlice);
        (, , , , , , , , YapOrderBook.OrderStatus aliceStatus) = yap.orders(
            orderIdAlice
        );
        (, , , , , , , , YapOrderBook.OrderStatus bobStatus) = yap.orders(
            orderIdBob
        );
        assertEq(
            uint8(aliceStatus),
            uint8(YapOrderBook.OrderStatus.PARTIAL_FILLED)
        );
        assertEq(uint8(bobStatus), uint8(YapOrderBook.OrderStatus.FILLED));
        assertEq(filledQuantity, 30e18);
    }

    function test_ClosePosition_Success() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        uint256 orderId = yap.createOrder(true, 50e18); // Alice creates LONG order
        uint256 escrowBalanceBefore = usdc.balanceOf(address(escrow));
        vm.warp(block.timestamp + 3 days); // Fast-forward to expiration
        vm.stopPrank();

        vm.prank(address(factory));
        yap.closePosition(orderId); // Close position
        uint256 escrowBalanceAfter = usdc.balanceOf(address(escrow));

        // Validate PnL settlement
        assertEq(escrowBalanceAfter, escrowBalanceBefore);
    }

    function test_EscrowBalanceInsufficient() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        yap.createOrder(true, 50e18); // Alice creates LONG order
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(escrow), 10e18);
        escrow.depositUserFund(10e18); // Insufficient deposit
        vm.expectRevert(YapEscrow.YE__InsufficientUserBalance.selector);
        yap.createOrder(false, 50e18); // Bob attempts to create SHORT order
        vm.stopPrank();
    }

    function test_CreateOrder_WithMaxUint256() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        vm.expectRevert();
        yap.createOrder(true, type(uint256).max); // Attempt to create an order with max uint256 size
        vm.stopPrank();
    }

    function test_CancelOrder_AfterFullFill() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        uint256 orderIdAlice = yap.createOrder(true, 50e18); // Alice creates LONG order
        vm.stopPrank();

        vm.startPrank(bob);
        usdc.approve(address(escrow), 51e18);
        escrow.depositUserFund(51e18); // Deposit funds into escrow
        yap.createOrder(false, 50e18); // Bob creates SHORT order
        vm.stopPrank();

        // Cancel after full fill
        vm.startPrank(alice);
        vm.expectRevert(YapOrderBook.YOB__InvalidOrder.selector);
        yap.cancelOrder(orderIdAlice); // Attempt to cancel a fully filled order
        vm.stopPrank();
    }

    function test_MatchOrders_WithZeroLiquidity() public {
        vm.startPrank(alice);
        usdc.approve(address(escrow), 100e18);
        escrow.depositUserFund(100e18); // Deposit funds into escrow
        yap.createOrder(true, 50e18); // Alice creates LONG order
        vm.stopPrank();

        vm.startPrank(bob);
        vm.expectRevert(YapEscrow.YE__InsufficientDeposit.selector);
        escrow.depositUserFund(0); // No funds deposited
        vm.stopPrank();
    }

    // function test_FeeCollection() public {
    //     vm.startPrank(alice);
    //     usdc.approve(address(escrow), 100e18);
    //     escrow.depositUserFund(100e18); // Deposit funds into escrow
    //     uint256 orderIdAlice = yap.createOrder(true, 50e18); // Alice creates LONG order
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     usdc.approve(address(escrow), 100e18);
    //     escrow.depositUserFund(100e18); // Deposit funds into escrow
    //     uint256 orderIdBob = yap.createOrder(false, 50e18); // Bob creates SHORT order
    //     vm.stopPrank();

    //     // Validate fee collection
    //     uint256 feeCollectorBalanceBefore = usdc.balanceOf(address(factory));
    //     vm.startPrank(address(factory));
    //     yap.closePosition(orderIdAlice);
    //     yap.closePosition(orderIdBob);
    //     vm.stopPrank();
    //     uint256 feeCollectorBalanceAfter = usdc.balanceOf(address(factory));

    //     assertTrue(feeCollectorBalanceAfter > feeCollectorBalanceBefore); // Fees should be collected
    // }

    function test_StressTest_LargeNumberOfOrders() public {
        uint256 numOrders = 100; // Simulate 100 orders
        for (uint256 i = 0; i < numOrders; i++) {
            address trader = address(uint160(i + 1));
            vm.startPrank(trader);
            deal(address(usdc), trader, 100e18); // Fund each trader
            usdc.approve(address(escrow), type(uint256).max); // Approve escrow
            escrow.depositUserFund(100e18); // Deposit funds into escrow
            yap.createOrder(i % 2 == 0, 50e18); // Alternate between LONG and SHORT
            vm.stopPrank();
        }

        // Validate active order count
        assertEq(yap.getActiveOrderCount(), numOrders);
    }

    // ===========================
    // Fuzz Testing
    // ===========================

    function testFuzz_CreateOrder_ValidSize(uint256 size) public {
        vm.assume(size > 0 && size <= 100e18); // Assume valid size range
        vm.startPrank(alice);
        usdc.approve(address(escrow), size);
        escrow.depositUserFund(size); // Deposit funds into escrow
        uint256 orderId = yap.createOrder(true, size); // Create order
        vm.stopPrank();

        (, , , , , uint256 quanty, , , ) = yap.orders(orderId);
        assertEq(quanty, size);
    }
}
