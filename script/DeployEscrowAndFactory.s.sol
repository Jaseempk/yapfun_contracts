//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
import {Script} from "forge-std/Script.sol";
import {YapEscrow} from "../src/YapEscrow.sol";
import {YapOrderBookFactory} from "../src/YapOrderBookFactory.sol";
import {LibRLP} from "solady/utils/LibRLP.sol";
import {console} from "forge-std/console.sol";

contract DeployEscrowAndFactory is Script {
    using LibRLP for address;

    uint256 pk = vm.envUint("METAMASK_PRIVATE_KEY");
    address deployer = vm.addr(pk);
    address usdc = 0x081827b8C3Aa05287b5aA2bC3051fbE638F33152;

    function run() public {
        vm.startBroadcast(pk);

        uint256 nonce = vm.getNonce(deployer);

        // Get the next two deployment addresses
        address escrowAddress = deployer.computeAddress(nonce); // nonce 1
        address factoryAddress = deployer.computeAddress(nonce + 1); // nonce 2

        console.log("Computed escrow address:", escrowAddress);
        console.log("Computed factory address:", factoryAddress);

        // Deploy escrow first with the pre-computed factory address
        YapEscrow escrow = new YapEscrow(
            usdc, // USDC
            factoryAddress
        );

        // Deploy factory with the actual escrow address
        YapOrderBookFactory factory = new YapOrderBookFactory(
            address(escrowAddress)
        );

        console.log("Actual escrow address:", address(escrow));
        console.log("Actual factory address:", address(factory));

        vm.stopBroadcast();
    }
}
