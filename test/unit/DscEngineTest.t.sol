// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";


contract DscEngineTest is Test {

    DeployDSC private deployer;
    DecentralizedStableCoin private dsc;
    DSCEngine private dsce;
    HelperConfig helperConfig;
    address wethTokenAddress;
    address wethUsdPriceFeedAddress;
    address wbtcTokenAddress;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, dsce, helperConfig) = deployer.run();
        (wethTokenAddress, wethUsdPriceFeedAddress, wbtcTokenAddress,,) = helperConfig.activeNetworkConfig();

        ERC20Mock(wethTokenAddress).mint(USER, STARTING_ERC20_BALANCE);
    }

    //////////////////////////////////////////////
    // Constructor tests
    //////////////////////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertsIfTokenLengthDoesNotMatchPriceFeed() public {
        tokenAddresses.push(wethTokenAddress);
        tokenAddresses.push(wbtcTokenAddress);
        priceFeedAddresses.push(wethUsdPriceFeedAddress);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }


    //////////////////////////////////////////////
    // Price feed tests
    //////////////////////////////////////////////

    function testGetUsdValue() public {

        uint256 ethAmount = 15e18;
        // 15e18 * 2000USD/ETH = 30,000e18;
        uint expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUsdValue(wethTokenAddress, ethAmount);
        assertEq(expectedUsd, actualUsd);    
    }

    function testGetTokenAmountFromUsd() public {
        uint256 usdAmountInWei = 1000e18;
        uint256 expectedTokenAmount =  5e17;
        uint256 actualTokenAmount = dsce.getTokenAmountFromUsd(wethTokenAddress, usdAmountInWei);
        assertEq(expectedTokenAmount, actualTokenAmount);
    }

    //////////////////////////////////////////////
    // depositCollateral tests
    //////////////////////////////////////////////

    function testDepositCollateralRevertsIfAmountCollateralParameterIsZero() public {        
        vm.startPrank(USER);
        ERC20Mock(wethTokenAddress).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositCollateral(wethTokenAddress, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_COLLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSC_Engine__TokenNotAllowed.selector);
        dsce.depositCollateral(address(ranToken), 100);        
        vm.stopPrank();
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(wethTokenAddress).approve(address(dsce), AMOUNT_COLLATERAL);  // in order to be able to deposit collateral, we need to do this
        dsce.depositCollateral(wethTokenAddress, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    /**
     * This is a functional test that asserts the account info is correctly populated once a user has deposited collateral.
     */
    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        uint256 expectedDscMinted = 0;
        // the expected usdCollateralValue should be linked to a value defined by the test itself, in this case from the AMOUNT_COLLATERAL as defined in the depositedCollateral modifier.
    
        (uint256 totalDscMinted, uint256 usdCollateralValue) = dsce.getAccountInformation(USER);

        uint256 tokenAmount = dsce.getTokenAmountFromUsd(wethTokenAddress, usdCollateralValue);

        assertEq(expectedDscMinted, totalDscMinted);
        assertEq(AMOUNT_COLLATERAL, tokenAmount);        
    }

}




