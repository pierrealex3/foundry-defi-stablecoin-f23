// SPDX-License-Identifier: MIT
// handler is going to narrow down the way we call functions

pragma solidity ^0.8.19;

import {Test, console} from "forge-std/Test.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine dsce;
    DecentralizedStableCoin dsc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    uint256 public timesMintIsCalled;
    address[] usersWhoDepositedCollateral = new address[](0);

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _decentralizedStableCoin) {
        dsce = _dscEngine;
        dsc = _decentralizedStableCoin;
    }

    // redeem collateral

    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {

        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);

        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        console.log("msg sender depositCollateral", msg.sender);

        vm.startPrank(msg.sender);
        collateralToken.mint(msg.sender, amountCollateral);
        collateralToken.approve(address(dsce), amountCollateral);

        dsce.depositCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
        // WARN: double push is possible
        usersWhoDepositedCollateral.push(msg.sender);
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral) public {

        console.log("msg sender redeemCollateral", msg.sender);       

        ERC20Mock collateralToken = _getCollateralFromSeed(collateralSeed);
        uint256 maxCollateralToRedeem = dsce.getCollateralBalanceOfUser(address(collateralToken), msg.sender);
        amountCollateral = bound(amountCollateral, 0, maxCollateralToRedeem);
        if (amountCollateral == 0) {  // disqualified for this test: it does represent a msg.sender that does not have any collateral, therefore CANNOT redeem because the dsce.redeemCollateral will revert!
            return;
        }
        
        vm.startPrank(msg.sender);
        dsce.redeemCollateral(address(collateralToken), amountCollateral);
        vm.stopPrank();
    }

    function mintDsc(uint256 amountDscToMint) public {

        if (usersWhoDepositedCollateral.length == 0) {
            return;
        }

        console.log("msg sender mintDsc", msg.sender);

        // choose randomly (based on the pseudo-random amountDscToMint seed) the user who has already deposited collateral so that our test call may at least have a chance to reach dsce.mintDsc below...
        address userWithinBank = usersWhoDepositedCollateral[amountDscToMint % usersWhoDepositedCollateral.length];
        console.log("msg sender FROM BANK mintDsc", userWithinBank);
        
        (uint256 totalDscMinted, uint256 usdCollateralValue) = dsce.getAccountInformation(userWithinBank);
        uint256 maxDscToMint = (usdCollateralValue / 2) - totalDscMinted;
        if (maxDscToMint <= 0) {
            return;
        }

        amountDscToMint = bound(amountDscToMint, 0, maxDscToMint);
        if (amountDscToMint == 0) {
            return;
        }

        vm.startPrank(userWithinBank);
        dsce.mintDsc(amountDscToMint);
        vm.stopPrank();

        timesMintIsCalled++;
    }

    // NOTE: a helper function that would provoke a change of price for a supported token would be a good thing to put in place.
    // However, running it would 100% break the protocol, because it cannot do nothing about a sudden plummeting of the collateral value.
    // This would result in the protool being broken i.e. UNDER collateralized and it couldn't do nothing about it.

    // Helper functions
    function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
        uint256 index = collateralSeed % 2;
        return ERC20Mock(dsce.getCollateralTokens()[index]);
    }

}