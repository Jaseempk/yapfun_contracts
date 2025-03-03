//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {YapOrderBook} from "../src/YapOrderBook.sol";

contract DeployYapOrderBook is Script {
    YapOrderBook orderBook;

    address _stablecoin = 0xC129124eA2Fd4D63C1Fc64059456D8f231eBbed1;
    address _feeCollector = 0x158aA738Bde109002D2597d844Bac5Be7f52D81d;
    address _escrow = 0xd2aCF386C6877dD5ad5d5735ca1D841459056a07;
    address _yapOracle = 0xDa1B4fFfAF462D5c39c2c06b33b1d400c0E04aB7;
    uint256 _kolId = 1100932506193260544;

    function run() public {
        vm.startBroadcast();
        orderBook = new YapOrderBook(
            _stablecoin,
            _feeCollector,
            _escrow,
            _yapOracle,
            _kolId
        );
        vm.stopBroadcast();
    }
}
