// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

/**
 * What are Our Invariants?:
 * 1. The total supply of DSC should be less than the total value of collateral
 * 2. Getter view functions should never revert <- evergreen invariant
 */
contract InvariantsTest is StdInvariant, Test {
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig helperConfig;
    address weth;
    address wbtc;
    Handler handler;
    uint256 constant RANDOM_AMOUNT = 1e8;

    function setUp() external {
        DeployDSC deployer = new DeployDSC();
        (dsc, dscEngine, helperConfig) = deployer.run();
        (,, weth, wbtc,) = helperConfig.activeNetworkConfig();
        handler = new Handler(dscEngine, dsc);
        targetContract(address(handler));
    }

    function invariant_protocolMustHaveMoreValueThanDebt() public view {
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(dscEngine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(dscEngine));

        uint256 wethValue = dscEngine.getUsdValue(weth, totalWethDeposited);
        uint256 wbtcValue = dscEngine.getUsdValue(wbtc, totalWbtcDeposited);

        console.log("weth value: ", wethValue);
        console.log("wbtc value: ", wbtcValue);
        console.log("total value: ", totalSupply);
        console.log("Times mint is called: ", handler.timesMintIscalled());

        assert(wethValue + wbtcValue >= totalSupply);
    }

    function invariant_gettersShouldNotRevert() public view {
        address randomUser = address(uint160(uint256(keccak256(abi.encodePacked(block.timestamp, block.number)))));
        address[] memory collateralTokens = dscEngine.getCollateralTokens();

        // User-dependent getters
        dscEngine.getAccountCollateralValue(randomUser);
        dscEngine.getAccountInformation(randomUser);
        dscEngine.getHealthFactor(randomUser);

        // Token-dependent getters for each collateral token
        for (uint256 i = 0; i < collateralTokens.length; i++) {
            address token = collateralTokens[i];
            dscEngine.getUsdValue(token, RANDOM_AMOUNT);
            dscEngine.getTokenAmountFromUsd(token, RANDOM_AMOUNT);
            dscEngine.getCollateralBalanceOfUser(token, randomUser);
            dscEngine.getCollateralTokenPriceFeed(token);
        }
    }
}
