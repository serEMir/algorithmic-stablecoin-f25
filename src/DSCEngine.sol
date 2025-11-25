// SPDX-License-Identifier: MIT

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

pragma solidity ^0.8.18;

/**
 * @title DSCEngine
 * @author SerEMir
 *
 * The system is designed to be as minimal as possible, and have tokens maintain a 1 token == $1 peg.
 * This stablecoin has the properties:
 * - Exogenous Collateral i.e collateral is not natively tied to the protocol e.g (ETH & BTC).
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees and was only backed by wETH and wBTC.
 *
 * Our DSC system should always be "overcollaterized". At no point should the value of all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the DSC system. It handles all the logic for minting and redeeming DSC, as well as depositing & withdrawing collateral.
 * @notice This contract is loosely based on MAKERDAO's DSS (DAI) system.
 */
import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {OracleLib} from "./libraries/OracleLib.sol";

contract DSCEngine is ReentrancyGuard {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorIsBroken(uint256 healthFactor);
    error DSCEngine__MintFailed();
    error DSCEngine__HealthFactorOK();
    error DSCEngine__HealthFactorNotImproved();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    using OracleLib for AggregatorV3Interface;

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    DecentralizedStableCoin private immutable i_dsc;

    uint256 private constant PRECISION = 1e18;
    uint256 private constant ADDITIONAL_PRECISION = 1e10;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% over collaterization
    uint256 private constant MIN_HEALTH_FACTOR = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10; // This means a 10% bonus
    address[] private s_collateralTokens;

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_collateralDeposited;
    mapping(address user => uint256 dscMinted) private s_dscMinted;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if (tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           PUBLIC & EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @param collateralTokenAddress The address of the token to deposit as collateral.
     * @param collateralAmount The amount of collateral to deposit.
     * @param amountOfDscToMint The amount of DSC to mint.
     * @notice This function will deposit a user's collateral and mint DSC in one transaction.
     */
    function depositCollateralAndMintDsc(
        address collateralTokenAddress,
        uint256 collateralAmount,
        uint256 amountOfDscToMint
    ) external {
        depositCollateral(collateralTokenAddress, collateralAmount);
        mintDsc(amountOfDscToMint);
    }

    /**
     * @param collateralTokenAddress The address of the collateral token to redeem
     * @param collateralAmount The amount of collateral to redeem
     * @param dscAmountToBurn The amount of DSC to burn
     * @notice This function will burn DSC and redeem underlying collateral in one transaction.
     */
    function redeemCollateralWithDsc(address collateralTokenAddress, uint256 collateralAmount, uint256 dscAmountToBurn)
        external
    {
        burnDsc(dscAmountToBurn);
        redeemCollateral(collateralTokenAddress, collateralAmount);
    }

    /**
     * @param collateralTokenAddress The address of the token to deposit as collateral
     * @param collateralAmount The amount of collateral to deposit
     * @notice only allowed tokens can be deposited. Make sure to check getCollateralTokens() for a list of all allowed tokens to avoid tx reversal
     * @notice make sure to approve DSCEngine to spend collateralAmount before calling this contract.
     */
    function depositCollateral(address collateralTokenAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        isAllowedToken(collateralTokenAddress)
        nonReentrant
    {
        s_collateralDeposited[msg.sender][collateralTokenAddress] += collateralAmount;

        emit CollateralDeposited(msg.sender, collateralTokenAddress, collateralAmount);

        bool success = IERC20(collateralTokenAddress).transferFrom(msg.sender, address(this), collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateral(address collateralTokenAddress, uint256 collateralAmount)
        public
        moreThanZero(collateralAmount)
        nonReentrant
    {
        _redeemCollateral(collateralTokenAddress, collateralAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice follows the "CEI" pattern
     * @param amountOfDscToMint The amount of Decentralized stable coin to mint
     * @notice caller must have more collateral value than the minimum threshold
     */
    function mintDsc(uint256 amountOfDscToMint) public moreThanZero(amountOfDscToMint) nonReentrant {
        s_dscMinted[msg.sender] += amountOfDscToMint;

        _revertIfHealthFactorIsBroken(msg.sender);
        bool minted = i_dsc.mint(msg.sender, amountOfDscToMint);
        if (!minted) {
            revert DSCEngine__MintFailed();
        }
    }

    /**
     * @notice make sure to approve this contract to spend the debToCover amount before calling this function.
     */
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); //this will likely never get hit.
    }

    /**
     * @param collateral The ERC20 address of the collateral to liquidate.
     * @param user The user who has broken the health factor.
     * @param debtToCover The amount of DSC you want to burn to improve the user's health factor.
     * @notice You can partially liquidate a user.
     * @notice You will get a liquidation bonus for paying off the user's debt.
     * @notice This function works under the assumption that the protocol will be roughly 200% overcollateralized at all times.
     * @notice This fucntion was designed to priotize minimizing the protocol's losses above anything else, even above the liquidators healthFactor.
     * @notice make sure to approve this contract to spend the debToCover amount before calling this function.
     */
    function liquidate(address collateral, address user, uint256 debtToCover)
        external
        moreThanZero(debtToCover)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOK();
        }

        uint256 maxDebtLiquitable = (s_dscMinted[user] * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 actualDebtCovered = debtToCover > maxDebtLiquitable ? maxDebtLiquitable : debtToCover;
        // amount of token equivalent to the USD price of debt owed by the user
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, actualDebtCovered);

        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;

        _redeemCollateral(collateral, totalCollateralToRedeem, user, msg.sender);

        _burnDsc(actualDebtCovered, user, msg.sender);

        // uint256 endingUserHealthFactor = _healthFactor(user);
        // if (endingUserHealthFactor <= startingUserHealthFactor) {
        //     revert DSCEngine__HealthFactorNotImproved();
        // }
        /**
         * revert this processs if it breaks liquidators healthFactor
         */
        // _revertIfHealthFactorIsBroken(msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Low-level internal function, do not call unless function calling it is checking for health factors being broken
     */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_dscMinted[onBehalfOf] -= amountDscToBurn;
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(address collateralTokenAddress, uint256 collateralAmount, address from, address to)
        private
    {
        s_collateralDeposited[from][collateralTokenAddress] -= collateralAmount;
        emit CollateralRedeemed(from, to, collateralTokenAddress, collateralAmount);

        bool success = IERC20(collateralTokenAddress).transfer(to, collateralAmount);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                     PRIVATE AND INTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _getAccountInformation(address user)
        private
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        totalDscMinted = s_dscMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    /**
     * Returns how close to liquidation a user is.
     * If a user goes below 1, then they can get liquidated.
     */
    function _healthFactor(address user) private view returns (uint256) {
        /**
         * This implementation works under the assumption that collateralValueInUsd >= $2
         */
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        if (totalDscMinted == 0) {
            return type(uint256).max;
        }
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    /**
     * @notice This function checks health factor (do they have enough collateral?).
     * And reverts if they don't.
     */
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorIsBroken(userHealthFactor);
        }
    }

    /*//////////////////////////////////////////////////////////////
                   PUBLIC AND EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getHealthFactor(address user) external view returns (uint256) {
        return _healthFactor(user);
    }

    function getAccountCollateralValue(address user) public view returns (uint256 totalCollateralValueInUsd) {
        for (uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_collateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getCollateralTokens() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return ((uint256(price) * ADDITIONAL_PRECISION) * amount) / PRECISION;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[token]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_PRECISION);
    }

    function getAccountInformation(address user)
        external
        view
        returns (uint256 totalDscMinted, uint256 collateralValueInUsd)
    {
        (totalDscMinted, collateralValueInUsd) = _getAccountInformation(user);
    }

    function getCollateralBalanceOfUser(address tokenCollateral, address user) public view returns (uint256) {
        return s_collateralDeposited[user][tokenCollateral];
    }

    function getCollateralTokenPriceFeed(address token) public view returns (address) {
        return s_priceFeeds[token];
    }
}
