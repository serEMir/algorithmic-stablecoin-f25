// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStableCoinTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine engine;

    address USER = makeAddr("user");
    uint256 public constant MINT_AMOUNT = 1 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine,) = deployer.run();

        vm.prank(address(engine));
        dsc.mint(address(engine), MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                               TEST MINT
    //////////////////////////////////////////////////////////////*/

    function testMintRevertIFNotCalledByDSCEngine() public {
        vm.prank(USER);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, USER));
        dsc.mint(USER, MINT_AMOUNT);

    }

    function testMintRevertsIfAddressZero() public {
        vm.prank(address(engine));
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__ZeroAddress.selector);
        dsc.mint(address(0), MINT_AMOUNT);
    }

    function testMintRevertsIfAmountZero() public {
        vm.prank(address(engine));
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.mint(USER, 0);
    }

    function testMintSuccessful() public {
        vm.prank(address(engine));
        dsc.mint(USER, MINT_AMOUNT);

        assertEq(dsc.balanceOf(USER), MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                               TEST BURN
    //////////////////////////////////////////////////////////////*/

    function testBurnRevertsIfAmountZero() public {
        vm.prank(address(engine));
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__MustBeMoreThanZero.selector);
        dsc.burn(0);
    }

    function testBurnRevertsIfAmountExceedsBalance() public {
        vm.prank(address(engine));
        vm.expectRevert(DecentralizedStableCoin.DecentralizedStableCoin__BurnAmountExceedsBalance.selector);
        dsc.burn(MINT_AMOUNT + 1);
    }

    function testBurnSuccessful() public {
        vm.prank(address(engine));
        dsc.burn(MINT_AMOUNT);

        assertEq(dsc.balanceOf(address(engine)), 0);
    }
}
