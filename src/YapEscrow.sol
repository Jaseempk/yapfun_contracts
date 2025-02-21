//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title YapEscrow
 * @author anon
 * @notice This contract manages the escrow process for Yap protocol, handling user fund deposits, order fulfillment, and profit/loss settlements.
 */
contract YapEscrow is AccessControl {
    //Error
    /**
     * @dev Reverts if the user's balance is insufficient.
     */
    error YE__InsufficientUserBalance();
    /**
     * @dev Reverts if the user's locked balance is insufficient.
     */
    error YE__InsufficientUserLockedBalance();

    error YE__InsufficientDeposit();

    error YE__InsufficientLockedBalance();

    bytes32 public constant WHITELIST_ROLE = keccak256("WHITELIST_ROLE");
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    /**
     * @dev The address of the USDC token.
     */
    address public immutable usdcAddress;

    /**
     * @dev Emitted when a user deposits funds.
     * @param user The address of the user.
     * @param depositAmount The amount of USDC deposited.
     * @param userBalance The user's balance after the deposit.
     * @param timeStamp The timestamp of the deposit.
     */
    event UserFundDeposited(
        address user,
        uint256 depositAmount,
        uint256 userBalance,
        uint256 timeStamp
    );

    /**
     * @dev Emitted when an order is fulfilled.
     * @param marketAddy The address of the market.
     * @param makerOrTakerAddy The address of the maker or taker.
     * @param amountFilled The amount of USDC transferred.
     */
    event OrderFulFilled(
        address marketAddy,
        address makerOrTakerAddy,
        uint256 amountFilled
    );
    /**
     * @dev Emitted when a user's balance is locked for an order.
     * @param userAddy The address of the user.
     * @param marketAddy The address of the market.
     * @param amountToLock The amount of USDC to lock.
     */
    event UserBalanceLocked(
        address userAddy,
        address marketAddy,
        uint256 amountToLock
    );

    /**
     * @dev Emitted when profit/loss is settled for a user.
     * @param user The address of the user.
     * @param market The address of the market.
     * @param settlingAmount The amount of USDC transferred.
     */
    event PnLSettled(address user, address market, uint256 settlingAmount);

    /**
     * @dev Emitted when a user's balance is unlocked from escrow
     * @param user Address of the user whose balance is being unlocked
     * @param marketAddy Address of the marketplace contract
     * @param balanceToFill Amount of tokens being unlocked
     */
    event UserBalanceUnlocked(
        address user,
        address marketAddy,
        uint256 balanceToFill
    );

    /**
     * @dev Mapping of user addresses to their balances.
     */
    mapping(address user => uint256 userBalance) public userToBalance;
    /**
     * @dev Mapping of user addresses to their locked balances for each market.
     */
    mapping(address user => mapping(address market => uint256 balance))
        public marketToLockedBalance;

    /**
     * @dev Initializes the contract with the USDC token address and grants roles.
     * @param _usdcAddress The address of the USDC token.
     * @param factory The address of the factory.
     */
    constructor(address _usdcAddress, address factory) {
        usdcAddress = _usdcAddress;
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Granting the default admin role to the contract deployer
        _grantRole(FACTORY_ROLE, factory); // Granting the factory role to the specified factory address
    }

    /**
     * @dev Allows a user to deposit USDC funds.
     * @param amountToDeposit The amount of USDC to deposit.
     */
    function depositUserFund(uint256 amountToDeposit) external {
        if (amountToDeposit == 0) revert YE__InsufficientDeposit();
        userToBalance[msg.sender] += amountToDeposit; // Updating the user's balance with the deposited amount
        emit UserFundDeposited(
            msg.sender,
            amountToDeposit,
            userToBalance[msg.sender], // Emitting the updated user balance
            block.timestamp // Emitting the timestamp of the deposit
        );
        IERC20(usdcAddress).transferFrom(
            msg.sender,
            address(this),
            amountToDeposit // Transferring the deposited amount from the user to the contract
        );
    }

    /**
     * @dev Fulfills an order using the user's balance.
     * @param orderAmountFilled The amount of USDC to transfer.
     * @param marketAddress The address of the market.
     * @param makerOrTakerAddy The address of the maker or taker.
     */
    function fulfillOrder(
        uint256 orderAmountFilled,
        address marketAddress,
        address makerOrTakerAddy
    ) external onlyRole(WHITELIST_ROLE) {
        if (userToBalance[makerOrTakerAddy] < orderAmountFilled)
            revert YE__InsufficientUserBalance(); // Reverting if the user's balance is insufficient

        userToBalance[makerOrTakerAddy] -= orderAmountFilled; // Deducting the order amount from the user's balance
        emit OrderFulFilled(marketAddress, makerOrTakerAddy, orderAmountFilled); // Emitting the order fulfillment event
        IERC20(usdcAddress).transfer(marketAddress, orderAmountFilled); // Transferring the order amount to the market address
    }

    /**
     * @dev Fulfills an order using the user's locked balance.
     * @param orderAmountFilled The amount of USDC to transfer.
     * @param marketAddress The address of the market.
     * @param makerOrTakerAddy The address of the maker or taker.
     */
    function fulfillOrderWithLockedBalance(
        uint256 orderAmountFilled,
        address marketAddress,
        address makerOrTakerAddy
    ) external onlyRole(WHITELIST_ROLE) {
        if (
            marketToLockedBalance[makerOrTakerAddy][marketAddress] <
            orderAmountFilled
        ) revert YE__InsufficientUserLockedBalance(); // Reverting if the user's locked balance is insufficient

        marketToLockedBalance[makerOrTakerAddy][
            marketAddress
        ] -= orderAmountFilled; // Deducting the order amount from the user's locked balance for the market
        emit OrderFulFilled(marketAddress, makerOrTakerAddy, orderAmountFilled); // Emitting the order fulfillment event
        IERC20(usdcAddress).transfer(marketAddress, orderAmountFilled); // Transferring the order amount to the market address
    }

    /**
     * @dev Locks a user's balance for an order.
     * @param balanceToFill The amount of USDC to lock.
     * @param marketAddy The address of the market.
     * @param makerOrTakerAddy The address of the maker or taker.
     */
    function lockTheBalanceToFill(
        uint256 balanceToFill,
        address marketAddy,
        address makerOrTakerAddy
    ) external onlyRole(WHITELIST_ROLE) {
        if (userToBalance[makerOrTakerAddy] < balanceToFill)
            revert YE__InsufficientUserBalance(); // Reverting if the user's balance is insufficient

        userToBalance[makerOrTakerAddy] -= balanceToFill; // Deducting the balance to fill from the user's balance
        marketToLockedBalance[makerOrTakerAddy][marketAddy] += balanceToFill; // Adding the balance to fill to the user's locked balance for the market
        emit UserBalanceLocked(makerOrTakerAddy, marketAddy, balanceToFill); // Emitting the user balance locked event
    }

    /// @notice Unlocks a specified amount of locked balance for a user after market expiry
    /// @dev Can only be called by addresses with WHITELIST_ROLE
    /// @param balanceToFill The amount of balance to unlock
    /// @param marketAddy The address of the market where balance is locked
    /// @param makerOrTakerAddy The address of the user (maker or taker) whose balance is being unlocked
    function unlockBalanceUponExpiry(
        uint256 balanceToFill,
        address marketAddy,
        address makerOrTakerAddy
    ) external onlyRole(WHITELIST_ROLE) {
        if (marketToLockedBalance[makerOrTakerAddy][marketAddy] < balanceToFill)
            revert YE__InsufficientLockedBalance(); //throws YE__InsufficientLockedBalance if locked balance is less than requested amount
        emit UserBalanceUnlocked(makerOrTakerAddy, marketAddy, balanceToFill); //emits UserBalanceUnlocked when balance is successfully unlocked
        marketToLockedBalance[makerOrTakerAddy][marketAddy] -= balanceToFill;
        userToBalance[makerOrTakerAddy] += balanceToFill;
    }

    /**
     * @dev Settles profit/loss for a user.
     * @param makerOrTakerAddy The address of the maker or taker.
     * @param settlingAmount The amount of USDC to transfer.
     * @param market The address of the market.
     */
    function settlePnL(
        address makerOrTakerAddy,
        uint256 settlingAmount,
        address market
    ) external onlyRole(WHITELIST_ROLE) {
        userToBalance[makerOrTakerAddy] += settlingAmount; // Adding the settling amount to the user's balance
        emit PnLSettled(makerOrTakerAddy, market, settlingAmount); // Emitting the profit/loss settlement event
        IERC20(usdcAddress).transfer(address(this), settlingAmount); // Transferring the settling amount to the contract address
    }

    /**
     * @dev Grants the whitelist role to a market.
     * @param marketOB The address of the market.
     */
    function whiteListmarketOB(
        address marketOB
    ) external onlyRole(FACTORY_ROLE) {
        _grantRole(WHITELIST_ROLE, marketOB); // Granting the whitelist role to the specified market address
    }

    /**
     * @dev Revokes the whitelist role from a market.
     * @param marketOB The address of the market.
     */
    function removeWhiteListmarketOB(
        address marketOB
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(WHITELIST_ROLE, marketOB); // Revoking the whitelist role from the specified market address
    }

    /// @notice Returns the balance of a specific user in the escrow contract
    /// @dev This function reads from the userToBalance mapping
    /// @param user The address of the user whose balance is being queried
    /// @return uint256 The current balance of the specified user
    function getUserBalance(address user) external view returns (uint256) {
        return userToBalance[user];
    }
}
