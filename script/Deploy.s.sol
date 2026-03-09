// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import {WeteEgoRouter} from "../src/WeteEgoRouter.sol";

contract DeployScript is Script {
    function run() external {
        address settlement = vm.envAddress("SETTLEMENT_ADDRESS");
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        WeteEgoRouter router = new WeteEgoRouter(settlement);
        vm.stopBroadcast();

        console.log("WeteEgoRouter deployed at:", address(router));
        console.log("Settlement address:", router.settlement());
    }
}
