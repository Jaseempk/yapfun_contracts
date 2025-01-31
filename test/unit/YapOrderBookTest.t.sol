//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {YapOrderBook} from "src/YapOrderBook.sol";
import {console} from "forge-std/console.sol";

contract YapOrderBookTest is Test {
    YapOrderBook yap;
    IERC20 usdc;
    address constant FEED = address(0xdead);
    address constant INSURANCE = address(0xbeef);

    address alice = address(0x1);
    address bob = address(0x2);
    address charlie = address(0x3);
    address admin = makeAddr("admin");

    function setUp() public {
        usdc = IERC20(0x081827b8C3Aa05287b5aA2bC3051fbE638F33152);
        deal(address(usdc), alice, 1000e18);
        deal(address(usdc), bob, 1000e18);
        deal(address(usdc), charlie, 1000e18);

        yap = new YapOrderBook(
            1, // influencerId
            block.timestamp + 1 weeks, // expiration
            address(usdc),
            FEED,
            INSURANCE,
            admin
        );
    }

    // Helper to get position ID
    function getPositionId(
        address trader,
        uint256 head,
        uint256 size,
        bool isLong,
        uint256 price
    ) internal view returns (bytes32) {
        // console.log("trader: ", trader);
        // console.log("head: ", head);
        // console.log("size: ", size);
        // console.log("isLong: ", isLong);
        // console.log("price: ", price);
        return
            keccak256(
                abi.encodePacked(
                    trader,
                    block.timestamp,
                    head,
                    size,
                    isLong,
                    price
                )
            );
    }

    function test_fullOrderBookMatch() public {
        // Alice opens short position
        vm.prank(alice);
        usdc.approve(address(yap), 1200e18);
        (uint256 _head, ) = yap.shortQueue();
        vm.prank(alice);
        yap.openPosition(100e18, false);

        // Bob matches with long
        vm.prank(bob);
        usdc.approve(address(yap), 130e18);
        vm.prank(bob);
        yap.openPosition(100e18, true);

        (uint256 head, ) = yap.longQueue();

        // Verify positions
        bytes32 alicePosId = getPositionId(
            alice,
            _head,
            100e18,
            false,
            37000000000000000
        );
        // console.log("Alice position ID: ");
        // console.logBytes32(alicePosId);
        bytes32 bobPosId = getPositionId(
            bob,
            head,
            100e18,
            true,
            37000000000000000
        );
        // console.log("Bob position ID: ");
        // console.logBytes32(bobPosId);
        (, uint256 size, , ) = yap.positions(alice, alicePosId);
        (, uint256 _size, , ) = yap.positions(bob, bobPosId);
        assertEq(size, 100e18);
        assertEq(_size, 100e18);
        assertEq(usdc.balanceOf(address(yap)), 200e18 + 1e18); // 1% fee on 100e18
    }

    function test_partialMatch_withPool() public {
        // Seed liquidity pool
        vm.prank(charlie);
        usdc.approve(address(yap), 50e18);
        vm.prank(charlie);
        yap.openPosition(50e18, true); // Adds to pool

        // Alice opens large short
        vm.prank(alice);
        usdc.approve(address(yap), 103e18);
        vm.prank(alice);
        yap.openPosition(100e18, false);

        console.log("fee collected:", yap.totalLiquidity());

        // Verify pool usage
        assertEq(yap.totalLiquidity(), 50e18 * 0.01); // 1% fee on pool usage
        (, uint256 tail) = yap.longQueue(); // Destructure the tuple
        assertEq(tail, 1); // Residual should be in queue
    }

    function test_positionProfit_andLoss() public {
        // Alice opens long
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        (uint256 head, ) = yap.shortQueue();
        vm.prank(alice);
        yap.openPosition(100e18, true);

        vm.prank(bob);
        usdc.approve(address(yap), 102e18);
        vm.prank(bob);
        yap.openPosition(100e18, false);

        // Verify positions
        bytes32 alicePosId = getPositionId(
            alice,
            head,
            100e18,
            true,
            37000000000000000
        );

        console.log("Alice position ID: ");
        console.logBytes32(alicePosId);

        vm.startPrank(alice);
        // Simulate price increase
        uint256 newPrice = 4e18; // 40% increase from 3.7e18
        vm.mockCall(
            address(yap),
            abi.encodeWithSelector(YapOrderBook._getOraclePrice.selector),
            abi.encode(newPrice)
        );
        // Close position with profit
        yap.closePosition(alicePosId);
        assertEq(yap._getOraclePrice(), newPrice);

        console.log("mocked price: ", yap._getOraclePrice());

        // Calculate expected PnL: (4 - 3.7) * 100e18 / 1e18 = 30e18
        uint256 expectedBalance = 1000e18 - 100e18 + 100e18 + 30e18;
        assertEq(usdc.balanceOf(alice), expectedBalance);
    }

    function test_queueManagement() public {
        // Add multiple orders
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            usdc.approve(address(yap), 120e18);
            vm.prank(alice);
            yap.openPosition(100e18, true);
        }

        // Process orders
        vm.prank(bob);
        usdc.approve(address(yap), 320e18);
        vm.prank(bob);
        yap.openPosition(300e18, false);

        // Verify queue state
        (uint256 head, uint256 tail) = yap.longQueue();
        assertEq(head, 3);
        assertEq(tail, 3);
    }

    function test_expiration() public {
        // Fast forward past expiration
        vm.warp(block.timestamp + 2 weeks);

        // Attempt to open position
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        vm.expectRevert(YapOrderBook.YOB__EXPIRED.selector);
        vm.prank(alice);
        yap.openPosition(100e18, true);
    }

    function test_insufficientLiquidity() public {
        // Alice tries to open position larger than pool
        vm.prank(alice);
        usdc.approve(address(yap), 1000e18);
        vm.expectRevert("!liquidity");
        vm.prank(alice);
        yap.openPosition(1000e18, true);
    }

    function test_zeroSize_position() public {
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        vm.expectRevert(YapOrderBook.YOB__INVALIDSIZE.selector);
        vm.prank(alice);
        yap.openPosition(0, true);
    }

    function test_closingNonExistentPosition() public {
        vm.expectRevert(YapOrderBook.YOB__INVALID_TRADER.selector);
        yap.closePosition(0x0);
    }

    function test_multiplePartialFills() public {
        // Seed multiple small orders
        for (uint256 i = 0; i < 5; i++) {
            vm.prank(bob);
            usdc.approve(address(yap), 20e18);
            vm.prank(bob);
            yap.openPosition(20e18, false);
        }

        // Open large position
        vm.prank(alice);
        usdc.approve(address(yap), 111e18);
        vm.prank(alice);
        yap.openPosition(110e18, true);

        // Verify queue state
        (uint256 head, uint256 tail) = yap.shortQueue();
        assertEq(head, 5);
        assertEq(tail, 5);
        assertEq(yap.totalLiquidity(), 1e18);
    }

    function test_frontRun_trade() public {
        // Initial order
        vm.prank(bob);
        usdc.approve(address(yap), 50e18);
        vm.prank(bob);
        yap.openPosition(50e18, false);

        // Attacker tries to front-run
        vm.prank(charlie);
        usdc.approve(address(yap), 1e18);
        vm.prank(charlie);
        yap.openPosition(1e18, false);

        // Alice's large order
        vm.prank(alice);
        usdc.approve(address(yap), 505e17);
        vm.prank(alice);
        yap.openPosition(50e18, true);

        (uint256 head, ) = yap.shortQueue();

        // Verify original order filled first
        assertEq(head, 1);
    }

    function test_positionIdCollision() public {
        // Freeze time for deterministic ID
        vm.warp(1641070800);

        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        (uint256 _head, ) = yap.longQueue();
        vm.prank(alice);
        yap.openPosition(100e18, true);

        // Attempt duplicate in same block
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        vm.prank(alice);
        yap.openPosition(100e18, true);
        (uint256 head, ) = yap.longQueue();

        // Verify positions
        bytes32 alicePosId1 = getPositionId(
            alice,
            _head,
            100e18,
            false,
            37000000000000000
        );

        bytes32 alicePosId2 = getPositionId(
            alice,
            head,
            100e18,
            true,
            37000000000000000
        );

        // Verify unique IDs

        assertTrue(alicePosId1 != alicePosId2);
    }
}
