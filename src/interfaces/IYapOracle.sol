// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IYapOracle {
    function getKOLData(uint256 kolId) external view returns (uint256, uint256, uint256, bool);
}
