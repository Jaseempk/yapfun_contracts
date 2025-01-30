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
            INSURANCE
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
        (uint256 size, , ) = yap.positions(alice, alicePosId);
        (uint256 _size, , ) = yap.positions(bob, bobPosId);
        assertEq(size, 100e18);
        assertEq(_size, 100e18);
        assertEq(usdc.balanceOf(address(yap)), 200e18 + 1e18); // 1% fee on 100e18 * 2
    }

    function testPartialMatchWithPool() public {
        // Seed liquidity pool
        vm.prank(charlie);
        usdc.approve(address(yap), 50e18);
        vm.prank(charlie);
        yap.openPosition(50e18, true); // Adds to pool

        // Alice opens large short
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        vm.prank(alice);
        yap.openPosition(100e18, false);

        // Verify pool usage
        assertEq(yap.totalLiquidity(), 50e18 * 0.05); // 5% fee on pool usage
        (, uint256 tail) = yap.longQueue(); // Destructure the tuple
        assertEq(tail, 1); // Residual should be in queue
    }

    function testPositionProfitAndLoss() public {
        // Alice opens long
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        vm.prank(alice);
        yap.openPosition(100e18, true);

        (uint256 head, ) = yap.longQueue();

        // Verify positions
        bytes32 alicePosId = getPositionId(
            alice,
            head,
            100e18,
            true,
            37000000000000000
        );

        // Simulate price increase
        uint256 newPrice = 4e18; // 40% increase from 3.7e18
        // vm.mockCall(
        //     FEED,
        //     abi.encodeWithSelector(
        //         AggregatorV3Interface.latestRoundData.selector
        //     ),
        //     abi.encode(0, int256(newPrice), 0, block.timestamp, 0)
        // );

        // Close position with profit
        vm.prank(alice);
        yap.closePosition(alicePosId);

        // Calculate expected PnL: (4 - 3.7) * 100e18 / 1e18 = 30e18
        uint256 expectedBalance = 1000e18 - 100e18 + 100e18 + 30e18;
        assertEq(usdc.balanceOf(alice), expectedBalance);
    }

    function testQueueManagement() public {
        // Add multiple orders
        for (uint256 i = 0; i < 3; i++) {
            vm.prank(alice);
            usdc.approve(address(yap), 100e18);
            vm.prank(alice);
            yap.openPosition(100e18, true);
        }

        // Process orders
        vm.prank(bob);
        usdc.approve(address(yap), 300e18);
        vm.prank(bob);
        yap.openPosition(300e18, false);

        // Verify queue state
        (uint256 head, uint256 tail) = yap.longQueue();
        assertEq(head, 3);
        assertEq(tail, 3);
    }

    function testExpiration() public {
        // Fast forward past expiration
        vm.warp(block.timestamp + 2 weeks);

        // Attempt to open position
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        vm.expectRevert("Expired");
        vm.prank(alice);
        yap.openPosition(100e18, true);
    }

    function testInsufficientLiquidity() public {
        // Alice tries to open position larger than pool
        vm.prank(alice);
        usdc.approve(address(yap), 1000e18);
        vm.expectRevert("!liquidity");
        vm.prank(alice);
        yap.openPosition(1000e18, true);
    }

    function testZeroSizePosition() public {
        vm.prank(alice);
        usdc.approve(address(yap), 100e18);
        vm.expectRevert();
        vm.prank(alice);
        yap.openPosition(0, true);
    }

    // function testLiquidation() public {
    //     // Alice opens position
    //     vm.prank(alice);
    //     usdc.approve(address(yap), 100e18);
    //     vm.prank(alice);
    //     yap.openPosition(100e18, true);

    //     bytes32 posId = getPositionId(alice, 100e18);

    //     // Simulate price drop below maintenance margin
    //     uint256 newPrice = 3.3e18; // 10% drop
    //     // vm.mockCall(
    //     //     FEED,
    //     //     abi.encodeWithSelector(
    //     //         AggregatorV3Interface.latestRoundData.selector
    //     //     ),
    //     //     abi.encode(0, int256(newPrice), 0, block.timestamp, 0)
    //     // );

    //     // Liquidate position
    //     vm.prank(bob);
    //     yap.liquidate(alice, posId);

    //     // Verify liquidation
    //     assertEq(yap.positions(alice, posId).size, 0);
    //     assertEq(usdc.balanceOf(bob), 1000e18 + 10e18); // 10% liquidation reward
    // }
}

/**
 * Logs:
  trader: 0x0000000000000000000000000000000000000001
  block.timestamp: 1738250160
  head: 0
  size: 100000000000000000000
  isLong: false
  price: 37000000000000000
  -----------------
  positionaId
  0xf599d4dea53f718b865107cf84acc5a1e05aca453990e5fed4331a9131fc3140
  -----------------
  trader: 0x0000000000000000000000000000000000000002
  block.timestamp: 1738250160
  head: 0
  size: 100000000000000000000
  isLong: true
  price: 37000000000000000
  -----------------
  positionaId
  0xd3ba75ec7d4d226a244888c80853e136abae26146fb38d0acc08de77b3f8ebf4
  -----------------
  trader:  0x0000000000000000000000000000000000000001
  head:  1
  size:  100000000000000000000
  isLong:  false
  price:  37000000000000000
  Alice position ID: 
  0xde25834b26b5f1367c98d23418fa3466d5d513971b2f1508d47fa6f589aaa730
  trader:  0x0000000000000000000000000000000000000002
  head:  0
  size:  100000000000000000000
  isLong:  true
  price:  37000000000000000
  Bob position ID: 
  0xd3ba75ec7d4d226a244888c80853e136abae26146fb38d0acc08de77b3f8ebf4

 */
