// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract HelperConfig is Script {

    struct NetworkConfig {
        address wethTokenAddress;
        address wethUsdPriceFeedAddress;
        address wbtcTokenAddress;
        address wbtcUsdPriceFeedAddress;
        uint256 deployerKey;
    }

    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;
    uint256 public constant DEFAULT_ANVIL_PRIVATE_KEY =  0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    NetworkConfig public activeNetworkConfig;
        
    constructor() {        
        if (block.chainid == 11155111) {
            activeNetworkConfig = getSepoliaEthNetworkConfig();
        } else {
            activeNetworkConfig = getOrCreateAnvilEthConfig();
        }
    }

    function getSepoliaEthNetworkConfig() public view returns (NetworkConfig memory) {
        return NetworkConfig({
            wethTokenAddress: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wethUsdPriceFeedAddress: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcTokenAddress: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wbtcUsdPriceFeedAddress: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43,
            deployerKey: vm.envUint("PRIVATE_KEY")
        });
    }

    function getOrCreateAnvilEthConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethTokenAddress != address(0)) { // I would normally use if activeNetworkConfig != null but we're in Solidity !!!
            return activeNetworkConfig;
        }

        // deploy ALL required mocks and return their addresses!
        vm.startBroadcast();
        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);

        ERC20Mock wethToken = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        ERC20Mock wbtcToken = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);

        vm.stopBroadcast();

        return NetworkConfig({
            wethTokenAddress: address(wethToken),
            wethUsdPriceFeedAddress: address(ethUsdPriceFeed),
            wbtcTokenAddress: address(wbtcToken),
            wbtcUsdPriceFeedAddress: address(btcUsdPriceFeed),
            deployerKey: DEFAULT_ANVIL_PRIVATE_KEY
        });
    }

}