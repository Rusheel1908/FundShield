// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {FundShield} from "../src/FundShield.sol";

/**
 * @title DeployFundShield
 * @notice Foundry deployment script.
 *         Run against Anvil (local) or any live network by swapping
 *         the --rpc-url and --private-key flags in the CLI command.
 */
contract DeployFundShield is Script {
    function run() external returns (FundShield fundShield) {
        // `vm.startBroadcast()` without an argument uses the private key
        // supplied via --private-key flag or the PRIVATE_KEY env variable.
        vm.startBroadcast();

        fundShield = new FundShield();

        console.log("FundShield deployed at:", address(fundShield));
        console.log("LARGE_AMOUNT_THRESHOLD:", fundShield.LARGE_AMOUNT_THRESHOLD());

        vm.stopBroadcast();
    }
}
