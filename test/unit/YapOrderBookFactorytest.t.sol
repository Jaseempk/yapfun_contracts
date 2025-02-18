//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YapOrderBookFactory} from "../../src/YapOrderBookFactory.sol";
import {YapEscrow} from "../../src/YapEscrow.sol";

contract YapOrderBookFactoryTest is Test {
    using LibRLP for address;
    YapOrderBookFactory newFactory;
    address oracleAddy = makeAddr("oracleAddy");

    YapEscrow escrow;
    YapOrderBookFactory factory;
    IERC20 usdc;

    function setUp() public {
        YapEscrow yapEscrowComputed = YapEscrow(
            address(this).computeAddress(2)
        );

        factory = new YapOrderBookFactory(address(yapEscrowComputed));

        escrow = new YapEscrow(address(usdc), address(factory));
        assertEq(address(yapEscrowComputed), address(escrow));
    }

    function test_initialiseNewmarket() public {
        uint256 kolId = 352372;

        newFactory.initialiseMarket(kolId, oracleAddy);
    }

    function test_initialiseMarket_revertOnNonAdmin() public {
        uint256 kolId = 673672;
        vm.prank(oracleAddy);
        vm.expectRevert();
        newFactory.initialiseMarket(kolId, oracleAddy);
    }
}
