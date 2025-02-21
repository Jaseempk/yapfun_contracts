//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IYapEscrow is IAccessControl {
    // Custom Errors
    error YE__InsufficientUserBalance();

    // Events
    event UserFundDeposited(
        address indexed user,
        uint256 depositAmount,
        uint256 userBalance,
        uint256 timeStamp
    );

    event OrderFulFilled(
        address indexed marketAddy,
        address indexed makerOrTakerAddy,
        uint256 amountFilled
    );

    event UserBalanceLocked(
        address indexed userAddy,
        address indexed marketAddy,
        uint256 amountToLock
    );

    // Roles
    function WHITELIST_ROLE() external view returns (bytes32);

    function FACTORY_ROLE() external view returns (bytes32);

    // State Variables
    function usdcAddress() external view returns (address);

    function userToBalance(address user) external view returns (uint256);

    function marketToLockedBalance(
        address user,
        address market
    ) external view returns (uint256);

    // Functions
    function depositUserFund(uint256 amountToDeposit) external;

    function fulfillOrder(
        uint256 orderAmountFilled,
        address marketAddress,
        address makerOrTakerAddy
    ) external;

    function fulfillOrderWithLockedBalance(
        uint256 orderAmountFilled,
        address marketAddress,
        address makerOrTakerAddy
    ) external;

    function lockTheBalanceToFill(
        uint256 balanceToFill,
        address marketAddy,
        address makerOrTakerAddy
    ) external;

    function settlePnL(
        address makerOrTakerAddy,
        uint256 pnlAmount,
        address market
    ) external;

    function unlockBalanceUponExpiry(
        uint256 balanceToFill,
        address marketAddy,
        address makerOrTakerAddy
    ) external;

    function getUserBalance(address user) external;

    function whiteListmarketOB(address marketOB) external;

    function removeWhiteListmarketOB(address marketOB) external;
}
