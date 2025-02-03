//SPDX-License-Identifier:MIT
pragma solidity ^0.8.24;

import {YapOrderBook} from "./YapOrderBook.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract YapOrderBookFactory is AccessControl{
    //error
    error YOBF__InvalidKolId();
    error YOBF__InvalidOracle(); 

    uint256 public constant TRADE_LIFECYCLE=3 days;
    address public constant USDC_ADDRESS=0x081827b8C3Aa05287b5aA2bC3051fbE638F33152;
    YapOrderBook newMarket;

    event NewMarketInitialised(uint256 kolId,address maker);

    constructor(){
        _grantRole(DEFAULT_ADMIN_ROLE,msg.sender);
    }


    function initialiseMarket(uint256 kolId,address _oracle)public onlyRole(DEFAULT_ADMIN_ROLE) {
        if(_oracle==address(0)) revert YOBF__InvalidOracle();
        if(kolId<=0) revert YOBF__InvalidKolId();
        emit NewMarketInitialised(kolId,msg.sender);
        newMarket=new YapOrderBook(kolId,TRADE_LIFECYCLE,USDC_ADDRESS,_oracle,msg.sender);
    }
}