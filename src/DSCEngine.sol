// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "src/libraries/OracleLib.sol";

/**
 * @title DSCEngine
 * @author PA Lemire
 * 
 * This system is designed to be as minimal as possible, and have the tokens maintain a 1 token == 1% peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral
 * - Dollar Pegged
 * - Algorithmically stable
 * 
 * It is similar to DAI if DAI had no governance, no fees, and was only backed by WETH and WBTC.
 * 
 * Our DSC system should always be "overcollateralized".  At no point, should the value of all collateral <= the $ backed value of all the DSC.
 * 
 * @notice This contract is the core of the DSC System.  It handles all the logic for minting and redeeming DCS, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {

    /** The big picture of how things should work to keep the DSC **SAFE**...
     * 
     * Threshold to let's say 150% (i.e. for $50 DSC, there must be $75 Collateral ex: WETH)
     * 
     * Scenario timeline:
     * The holder meets the threshold.  He has $100 ETH and $50 DSC
     * 
     * The collateral value crashes!  The $100 ETH is now worth $74.
     * The holder does not meet the threshold.  He has $40 ETH and $50 DSC
     * This user should be liquidated and not be allowed to hold a position in the system anymore!
     * 
     * HEY! If someone pays back your minted DSC, they can have all your collateral for a discount.
     * 
     * Mister X says: I'll pay back the $50 DSC and get ALL your collateral!
     * Then Mister X burns $50 of DSC and gets the $74 worth of ETH.
     * Mister X gets $24 worth of profit.
     * The holder lost everything?
     * 
     * Holder has a punishment for letting his collateral get too low.
     * Liquidator has a reward for liquidating the holder position in order to keep the DSC safe.
     * 
     */

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% OVER collateralized
    uint256 private constant LIQUIDATION_PRECISION = 1e2; 
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // to be used as 10%

    // collateral
    mapping(address token => address priceFeed) private s_priceFeeds; // tokenToPriceFeed
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    address[] private s_collateralTokens;

    // decentralized stablecoin
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted; // ??? why not use the i_dsc.balanceOf(user) to get that info ???    
    DecentralizedStableCoin private immutable i_dsc;

    error DSCEngine__NeedsMoreThanZero();
    error DSC_Engine__TokenNotAllowed();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    //////////////////////
    // Types
    //////////////////////

    using OracleLib for AggregatorV3Interface;

    //////////////////////
    // Events
    //////////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount);
    event DSCBurned(address indexed user, uint256 indexed amount);

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;       
    }

    modifier isAllowedToken(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSC_Engine__TokenNotAllowed();
        }
        _;
    }

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        // Could there be a sanity check done upon the DEPLOY transaction and revert it if unsane???  YES!
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        // USD Price Feeds ex: BTC/USD ETH/USD
        for (uint256 i=0; i<tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////////////////////////////////////
    // EXTERNAL FUNCTIONS
    //////////////////////////////////////////////

    /**
     * @param tokenCollateralAddress The address of the token to deposit as a collateral.
     * @param amountCollateral The amount of collateral to deposit.
     * @param amountDscToMint The amount of decentralized stablecoin to mint.
     * @notice This function will deposit your collateral and mint DSC in a single transaction.
     */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /**
     * @param tokenCollateralAddress The address of the token to deposit as a collateral.
     * @param amountCollateral The amount of collateral to deposit.
     * @notice follows CEI pattern
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {
        // validate the tokenCollateral is allowed (address whitelisting via modifiers)
        // Adjust the collateral balance of the user in this contract storage.
        // transfer ownership on the ERC20 contract for the selected collateral (WETH or WBTC) -> ERC20(tokenCollateralAddress).transfer(amountCollateral, address(this))
        // DecentralizedStableCoin(dscAddress).mint(msg.sender, conversion(amountCollateral)) <== THIS WON'T BE DONE HERE, BUT LATER ON, ON DEMAND!

        s_collateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);  // will this call succeed if IERC20.approve is not called beforehand?
        if (!success) {
            revert DSCEngine__TransferFailed();
        }

    }

    /**
     * @param tokenCollateralAddress The address of the token to redeem.
     * @param amountCollateral  The amount of collateral to redeem.
     * @param amountDscToBurn The amount of DSC to burn.
     * @notice This function burns DSC and redeems collateral in a single transaction.
     */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) external isAllowedToken(tokenCollateralAddress) moreThanZero(amountCollateral) moreThanZero(amountDscToBurn) {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral already checks on the health factor!
    }

    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant {        
        // In ORDER to redeem collateral:
        // 1. the health factor must be over 1 AFTER collateral pulled
        // burn all the stablecoin of the user
        // transfer back all the collateral to the user
        // and make sure all the mappings are cleaned from the user presence

        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @param amountDscToMint The amount of decentralized stablecoin to mint
     * @notice must have more collateral value than the minimum threshold
     * @notice follows CEI pattern
     */
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {

        // check if the USD collateral value > dsc value by a specified threshold
        //    to do this, go fetch the collateral value from a CL feed
        // If all good, mint the DecentralizedStableCoin -> dsc.mint(msg.sender, usdCollateralValue)
        // Otherwise, revert!

        s_DSCMinted[msg.sender] += amountDscToMint;

        // if they minted too much as per threshold, revert!
        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }

    }

    function burnDsc(uint256 amount) public moreThanZero(amount) {                
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);  // I don't think this would ever hit...
        emit DSCBurned(msg.sender, amount);
    }

    // If someone is almost undercollateralized, we will pay you to liquidate them.
    // In the following scenario:
    // $75 collateral backing $50 DSC
    // Liquidator takes $75 backing and burns off the $50 DSC

    /**
     * Liquidate
     * @param tokenCollateralAddress The erc20 collateral address to liquidate from the user.
     * @param userToLiquidate The user who has broken the health factor.  Their health factor needs to be below MIN_HEALTH_FACTOR to be eligible for liquidation.
     * @param debtToCover The amount of DSC you want to burn to improve the users health factor.
     * @notice You can partially liquidate a user, as long as you improve their health factor.
     * @notice You will get a liquidation bonus for taking the users funds.
     * @notice This function working assumes the protocol will be roughly 200% overcollateralized in order for this to work.
     * @notice A known bug would be if the protocol were 100% or less collateralized, then we wouldn't be able to incentivize the liquidators.
     * For example, if the price of the collateral plummeted before anyone could be liqudated.
     */
    function liquidate(address tokenCollateralAddress, address userToLiquidate, uint256 debtToCover) external moreThanZero(debtToCover) isAllowedToken(tokenCollateralAddress) nonReentrant {

        uint256 startingHealthFactor = _healthFactor(userToLiquidate);

        if (startingHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }

        // We want to burn their DSC "debt" and take their collateral.
        //uint256 collateralAmountBefore = s_collateralDeposited[userToLiquidate][tokenCollateralAddress];
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(tokenCollateralAddress, debtToCover);

        // And give them a 10% bonus.
        // So we are giving the liquidator $110 of WETH for $100 DSC
        // We should implement a feature to liquidate in the event the protocol is insolvent. (meaning liquidate all by itself ???)
        // And sweep extra amounts into a treasury (for the protocol to become solvent once again)
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalTokenAmountGiveaway = tokenAmountFromDebtCovered + bonusCollateral;

        // redeem and burn!
        _redeemCollateral(userToLiquidate, msg.sender, tokenCollateralAddress, totalTokenAmountGiveaway);
        _burnDsc(debtToCover, userToLiquidate, msg.sender);  // msg.sender is going to pay for that i.e. be on the "from" side upon the IERC20(dsc).transferFrom call
        
        uint256 endingHealthFactor = _healthFactor(userToLiquidate);
        if (endingHealthFactor <= startingHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);  // do not let the liquidator ruin his own health factor

    }


    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }
    
    //////////////////////////////////////////////
    // PRIVATE and INTERNAL functions
    //////////////////////////////////////////////

    /**
     * @dev Low-level internal function.  Do not call unless the function calling it is checking for health factors being broken.
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        // This condition is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }


    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private {
        s_collateralDeposited[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral); // from does not own the collateral.  address(this) does.
        if (!success) {
            revert DSCEngine__TransferFailed();            
        }
    }



    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256 equivalentAmountOfCollateral) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // this is documented in: docs.chain.link/data-feeds/price-feeds/addresses ->
        equivalentAmountOfCollateral = (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);        
    }

    function _getAccountInformation(address user) private view returns (uint256 totalDscMinted, uint256 usdCollateralValue) {
        totalDscMinted = s_DSCMinted[user];
        usdCollateralValue = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to LIQUIDATION a user is.
     * If a user goes below 1, they can get liquidated.
     * @param user the user to check for.
     * @return the health factor as 0 (BAD) or >0 (GOOD)
     */
    function _healthFactor(address user) private view returns (uint256) {
        // total DSC minted
        // total collateral $VALUE
        (uint256 totalDscMinted, uint256 usdCollateralValue) = _getAccountInformation(user);

        // return BAD if (usdCollateralValue / totalDscMinted) * 100 < THRESHOLD (say thershold is 150 i.e. (1.5 * 100))
        // ex:
        // 150 i.e. 1.50 with precision 2        
        // BAD WOULD BE ==> usdCollateralValue * 1e2 /*threshold precision*/ / totalDscMinted * 1e18 < 150
        // otherwise return GOOD

        // BAD scenario: UNDER collateralized
        // $150 ETH / 100 DSC = 1.5
        // 150 * 50 = 7500 / 100 = 75 / 100 < 1 (Solidity would truncate and render 0)

        // GOOD scenario: OVER collateralized
        // $1000 ETH / 100 DSC = 10
        // 1000 * 50 = 50000 / 100 = 500 / 100 > 1
        
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }

        uint256 collateralAdjustedForThreshold = (usdCollateralValue * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;

    }


    function _revertIfHealthFactorIsBroken(address user) internal view {
        // 1. check health factor (do they have enough collateral?)
        uint256 userHealthFactor = _healthFactor(user);
        
        // 2. revert if there is not enough collateral
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__BreaksHealthFactor(userHealthFactor);
        }
    }

    //////////////////////////////////////////////
    // PUBLIC and EXTERNAL VIEW functions
    //////////////////////////////////////////////

    /**
     * Return all the collateral value (in USD) associated to the user.
     * @param user The user for which the collateral value is asked for.
     */
    function getAccountCollateralValue(address user) public view returns(uint256 totalCollateralValue) {

        // loop through the collateral values and fetch their value
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 collateralAmount = s_collateralDeposited[user][token];
            if (collateralAmount > 0) {
                totalCollateralValue += getUsdValue(token, collateralAmount);
            }
        }

    }

    /**
     * Return the collateral value (in USD - w/o the cents) of a specified token, for the volume specified.
     * @param token the ERC20 token address
     * @param amount the token amount in Wei - precision is therefore 18. For example: 55.55 ETH is represented as uint256 -> 55 55000000 0000000000
     */
    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (,int256 price,,,) = priceFeed.staleCheckLatestRoundData();
        // this is documented in: docs.chain.link/data-feeds/price-feeds/addresses -> there are 8 DECIMAL PLACES for ETH (BTC as well)
        // If 1 ETH = $1000, then the returned value from CL will be 1000 * 1e8
        return (uint256(price) * ADDITIONAL_FEED_PRECISION * amount) / PRECISION; // ( (1000 * 1e8) * 1e10 * (1000 * 1e18) ) / 1e18;

    }

    function getAccountInformation(address user) external view returns (uint256 totalDscMinted, uint256 usdCollateralValue) {
        (totalDscMinted, usdCollateralValue) = _getAccountInformation(user);
    }

    function getCollateralTokens() external view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralBalanceOfUser(address token, address user) external view returns (uint256) {
        return s_collateralDeposited[user][token];
    }

}