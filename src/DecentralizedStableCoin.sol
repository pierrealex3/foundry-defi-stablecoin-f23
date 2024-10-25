// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

/**
 * @title 
 * @author 
 * @notice
 * This contract is meant to be governed by the DSCEngine.
 * It is just the ERC-20 implementation of our STABLECOIN SYSTEM.
 */
contract DecentralizedStableCoin is ERC20Burnable, Ownable {

    error DecentralizedStableCoin__MustBeMoreThanZero();
    error DecentralizedStableCoin__BurnAmountExceedsBalance();
    error DecentralizedStableCoin__NotZeroAddress();


    constructor() ERC20("DecentralizedStableCoin", "DSC") {}

    function burn(uint256 amount) public override onlyOwner {

        if (amount == 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }        

        uint256 balance = balanceOf(msg.sender);

        if (balance < amount) {
            revert DecentralizedStableCoin__BurnAmountExceedsBalance();
        }

        super.burn(amount);
    }

    function mint(address to, uint256 amount) external onlyOwner returns (bool) {
        if (amount == 0) {
            revert DecentralizedStableCoin__MustBeMoreThanZero();
        }
        if (to == address(0)) {
            revert DecentralizedStableCoin__NotZeroAddress();
        }
        _mint(to, amount);
        return true;

    }



}