// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../../test/mocks/MockV3Aggregator.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DSCEngine dscEngine;
    DecentralizedStableCoin dsc;
    HelperConfig helperConfig;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    int256 public constant NEW_ETH_USD_PRICE = 1000e8;
    int256 public constant NEW_ETH_USD_PRICE2 = 4000e8;

    address USER = makeAddr("user");
    address USER2 = makeAddr("user2");
    uint256 public constant COLLATERAL_AMOUNT = 10 ether;
    uint256 public constant COLLATERAL_AMOUNT2 = 10 ether;
    uint256 public constant MINT_AMOUNT = (COLLATERAL_AMOUNT * 4000) / 4;
    uint256 public constant STARTING_WETH_BALANCE = 100 ether;
    uint256 public constant STARTING_WBTC_BALANCE = 100 ether;
    uint256 public constant DEBT_TO_COVER = 4000 ether;
    uint256 public constant DEBT_TO_COVER2 = 10000 ether;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = helperConfig.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_WETH_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_WETH_BALANCE);

        ERC20Mock(weth).mint(USER2, STARTING_WETH_BALANCE);
        ERC20Mock(wbtc).mint(USER2, STARTING_WETH_BALANCE);

        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_WETH_BALANCE);
        ERC20Mock(wbtc).approve(address(dscEngine), STARTING_WBTC_BALANCE);
        vm.stopPrank();

        vm.startPrank(USER2);
        ERC20Mock(weth).approve(address(dscEngine), STARTING_WETH_BALANCE);
        ERC20Mock(wbtc).approve(address(dscEngine), STARTING_WBTC_BALANCE);
        vm.stopPrank();

        vm.deal(address(dscEngine), STARTING_WETH_BALANCE);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier depositedCollateral() {
        vm.startPrank(USER);
        dscEngine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDsc() {
        vm.startPrank(USER);
        dscEngine.depositCollateralAndMintDsc(weth, COLLATERAL_AMOUNT, MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier prepToLiquidate() {
        vm.startPrank(USER2);
        dscEngine.depositCollateral(weth, COLLATERAL_AMOUNT2);
        dscEngine.mintDsc(MINT_AMOUNT);
        dsc.approve(address(dscEngine), MINT_AMOUNT);
        vm.stopPrank();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    function testRevertsIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    /*//////////////////////////////////////////////////////////////
                            PRICE FEED TESTS
    //////////////////////////////////////////////////////////////*/

    function testGetUsdValue() public view {
        uint256 ethAmount = 5e18;
        uint256 expectedUsd = 20_000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 2000 ether;
        uint256 expectedWeth = 0.5 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    /*//////////////////////////////////////////////////////////////
                            DEPOSIT COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertIfCollateralZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock();
        vm.startPrank(USER);
        ERC20Mock(ranToken).approve(address(dscEngine), COLLATERAL_AMOUNT);

        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), COLLATERAL_AMOUNT);
    }

    function testCanDepositCollateralAndGetAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);

        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    function testDepositCollateralEmits() public depositedCollateral {
        vm.startPrank(USER);
        vm.expectEmit(true, true, true, false);
        emit DSCEngine.CollateralDeposited(USER, weth, COLLATERAL_AMOUNT);

        dscEngine.depositCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndMintDsc() public depositCollateralAndMintDsc {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);
        uint256 expectedDepositAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, MINT_AMOUNT);
        assertEq(COLLATERAL_AMOUNT, expectedDepositAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT DSC TESTS
    //////////////////////////////////////////////////////////////*/

    function testRevertIfMintAmountZero() public {
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.mintDsc(0);
    }

    function testMintDscRevertsIfHealthFactorBroken() public {
        /**
         * This test is meant to check that a new user can't mint dsc if they haven't deposited collateral
         */
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));
        dscEngine.mintDsc(1 ether);
        vm.stopPrank();
    }

    function testDscMints() public depositCollateralAndMintDsc {
        (uint256 totalDscMinted,) = dscEngine.getAccountInformation(USER);
        assertEq(totalDscMinted, MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            REDEEM COLLATERAL TESTS
    //////////////////////////////////////////////////////////////*/

    function testRedeemCollateralRevertsIfHealthFactorBroken() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__HealthFactorIsBroken.selector, 0));
        dscEngine.redeemCollateral(weth, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }

    function testRedeemCollateral() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        dscEngine.redeemCollateral(weth, 1 ether);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                                BURN DSC
    //////////////////////////////////////////////////////////////*/

    function testBurnDsc() public depositCollateralAndMintDsc {
        vm.startPrank(USER);
        dsc.approve(address(dscEngine), MINT_AMOUNT);
        console.log(dsc.balanceOf(USER));
        dscEngine.burnDsc(MINT_AMOUNT);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            LIQUIDATE TESTS
    //////////////////////////////////////////////////////////////*/

    function testLiquidateRevertsIfUserHealthFactotrOk() public depositCollateralAndMintDsc {
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorOK.selector);
        dscEngine.liquidate(weth, USER, DEBT_TO_COVER);
    }

    // function testLiquidateRevertsIfUserHealthFactorNotImproved() public depositCollateralAndMintDsc prepToLiquidate {
    //     vm.startPrank(USER2);
    //     vm.expectRevert(DSCEngine.DSCEngine__HealthFactorNotImproved.selector);
    //     dscEngine.liquidate(weth, USER, DEBT_TO_COVER);
    //     vm.stopPrank();
    // }

    function testCanLiquidate() public depositCollateralAndMintDsc prepToLiquidate {
        MockV3Aggregator(ethUsdPriceFeed).updateAnswer(NEW_ETH_USD_PRICE);

        vm.startPrank(USER2);
        dscEngine.liquidate(weth, USER, DEBT_TO_COVER2);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         TEST GETTER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function testGetAccountCollateralValue() public depositedCollateral {
        vm.startPrank(USER);
        dscEngine.depositCollateral(wbtc, COLLATERAL_AMOUNT);
        vm.stopPrank();
    }
}
