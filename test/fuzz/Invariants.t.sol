// SPDX-License-Identifier: MIT

// What are our invariants?
// 1. The total supply of DSC should be less thant the total value of collateral
// 2. Getter view functions should never revert

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "test/fuzz/Handler.t.sol";


contract InvariantsTest is StdInvariant, Test {

    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address wbtc;
    Handler handler;
    

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (weth,,wbtc,,) = config.activeNetworkConfig();
        //targetContract(address(dsce));
        handler = new Handler(dsce, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view  {

        // get the value of all the collateral in the protocol
        // compare it to all the debt (dsc)
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dsce));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dsce));
        uint256 totalWethUsdValue = dsce.getUsdValue(weth, totalWethDeposited);
        uint256 totalWbtcUsdValue = dsce.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", totalWethUsdValue);
        console.log("wbtc value: ", totalWbtcUsdValue);
        console.log("total supply: ", totalSupply);
        console.log("Times mint called: ", handler.timesMintIsCalled());

        assert(totalWbtcUsdValue + totalWethUsdValue >= totalSupply);
    }
    
}

