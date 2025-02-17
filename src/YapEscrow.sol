//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract YapEscrow {
    address public immutable usdcAddress;

    event UserFundDeposited(
        address user,
        uint256 depositAmount,
        uint256 userBalance,
        uint256 timeStamp
    );

    mapping(address user => uint256 userBalance) public userToBalance;

    constructor(address _usdcAddress) {
        usdcAddress = _usdcAddress;
    }

    function depositUserFund(uint256 amountToDeposit) external {
        userToBalance[msg.sender] += amountToDeposit;
        emit UserFundDeposited(
            msg.sender,
            amountToDeposit,
            userToBalance[msg.sender],
            block.timestamp
        );
        IERC20(usdcAddress).transferFrom(
            msg.sender,
            address(this),
            amountToDeposit
        );
    }

    function fulfillOrder(
        uint256 orderAmountFilled,
        address marketAddress,
        address makerOrTakerAddy
    ) public {}
}

/**
 * objectives:
 * users deposit the trade amount to this contract, contract tracks the user balance.
 * when the openPosition is called in the orderbook the funds are send from the escrow to the OB, the partially filled balance is locked until it's either cancelled or expired
 */
