//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {YapOrderBook} from "./YapOrderBook.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {IYapEscrow} from "./interfaces/IYapEscrow.sol";

contract YapOrderBookFactory is AccessControl {
    //error
    error YOBF__InvalidKolId();
    error YOBF__InvalidOracle();

    IYapEscrow yapEscrow;

    uint256 public constant TRADE_LIFECYCLE = 3 days;
    address public constant USDC_ADDRESS =
        0x081827b8C3Aa05287b5aA2bC3051fbE638F33152;
    YapOrderBook newMarket;

    event NewMarketInitialisedAndWhitelisted(
        uint256 kolId,
        address maker,
        address marketAddy
    );

    constructor(address _yapEscrow) {
        yapEscrow = IYapEscrow(_yapEscrow);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function initialiseMarket(
        uint256 kolId,
        address _oracle
    ) public onlyRole(DEFAULT_ADMIN_ROLE) returns (address) {
        if (_oracle == address(0)) revert YOBF__InvalidOracle();
        if (kolId <= 0) revert YOBF__InvalidKolId();
        newMarket = new YapOrderBook(
            kolId,
            TRADE_LIFECYCLE,
            USDC_ADDRESS,
            _oracle,
            msg.sender,
            address(yapEscrow)
        );
        emit NewMarketInitialisedAndWhitelisted(
            kolId,
            msg.sender,
            address(newMarket)
        );
        yapEscrow.whiteListmarketOB(address(newMarket));

        return address(newMarket);
    }
}
