// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {

    address[] private s_tokenAddresses;
    address[] private s_priceFeedAddresses;

    function run() external returns (DecentralizedStableCoin, DSCEngine, HelperConfig) {

        HelperConfig helperConfig = new HelperConfig();

        (address wethTokenAddress, address wethUsdPriceFeedAddress, address wbtcTokenAddress, address wbtcUsdPriceFeedAddress, uint256 deployerKey) = helperConfig.activeNetworkConfig();
        
        s_tokenAddresses = [wethTokenAddress, wbtcTokenAddress];
        s_priceFeedAddresses = [wethUsdPriceFeedAddress, wbtcUsdPriceFeedAddress];
        
        vm.startBroadcast(deployerKey);
        DecentralizedStableCoin dsc = new DecentralizedStableCoin();
        DSCEngine dscEngine = new DSCEngine(s_tokenAddresses, s_priceFeedAddresses, address(dsc));
        dsc.transferOwnership(address(dscEngine));
        vm.stopBroadcast();

        return (dsc, dscEngine, helperConfig);
    }
}