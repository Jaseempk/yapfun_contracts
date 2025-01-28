//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {YapOracle} from "src/YapOracle.sol";

contract YapOracleTest is Test {
    YapOracle oracle;

    function setUp() public {
        oracle = new YapOracle(address(this));
    }

    function testUpdateKOLData() public {
        uint256[] memory kolIds = new uint256[](1);
        uint256[] memory ranks = new uint256[](1);
        uint256[] memory mindshareScores = new uint256[](1);

        kolIds[0] = 1;
        ranks[0] = 1;
        mindshareScores[0] = 1;

        oracle.updateKOLData(kolIds, ranks, mindshareScores);
        (uint256 rank, uint256 mindshareScore, , ) = oracle.kolData(1);
        assertEq(rank, 1);
        assertEq(mindshareScore, 1);
    }
}
