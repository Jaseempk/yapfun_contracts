//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";

import {YapOrderBookFactory} from "../../src/YapOrderBookFactory.sol";

contract YapOrderBookFactoryTest is Test{

    YapOrderBookFactory newFactory;
    address oracleAddy=makeAddr("oracleAddy");

    function setUp()public {
        newFactory=new YapOrderBookFactory();
    }

    function test_initialiseNewmarket()public{
        uint256 kolId=352372;

        newFactory.initialiseMarket(kolId,oracleAddy);

    }

    function test_initialiseMarket_revertOnNonAdmin()public{
        uint256 kolId=673672;
        vm.prank(oracleAddy);
        vm.expectRevert();
        newFactory.initialiseMarket(kolId,oracleAddy);
    }
}