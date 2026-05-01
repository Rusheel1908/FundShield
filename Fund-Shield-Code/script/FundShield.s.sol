// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {FundShield} from "../src/FundShield.sol";

/**
 * @title DeployFundShield
 * @notice Foundry deployment script.
 *
 * Chainlink ETH/USD price feed addresses:
 *   Sepolia  : 0x694AA1769357215DE4FAC081bf1f309aDC325306
 *   Mainnet  : 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419
 *
 * Override the feed address with the PRICE_FEED env var:
 *   PRICE_FEED=0x... forge script script/FundShield.s.sol --rpc-url <RPC> --broadcast
 */
contract DeployFundShield is Script {
    // Sepolia ETH/USD feed — used as default when PRICE_FEED env var is not set
    address internal constant SEPOLIA_ETH_USD = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    function run() external returns (FundShield fundShield) {
        address priceFeed = vm.envOr("PRICE_FEED", SEPOLIA_ETH_USD);

        vm.startBroadcast();

        fundShield = new FundShield(priceFeed);

        console.log("FundShield deployed at  :", address(fundShield));
        console.log("Owner                   :", fundShield.owner());
        console.log("Price feed              :", address(fundShield.priceFeed()));
        console.log("Large amount threshold  : $", fundShield.largeAmountThresholdUSD() / 1e8, "USD");

        vm.stopBroadcast();
    }
}
