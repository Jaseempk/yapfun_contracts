//SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {YapOracle} from "../src/YapOracle.sol";

contract DeployYapOracle is Script {
    YapOracle newOracle;
    address updater = 0x66aAf3098E1eB1F24348e84F509d8bcfD92D0620;

    function run() public {
        vm.startBroadcast();
        newOracle = new YapOracle(updater);
        vm.stopBroadcast();
    }
}
