// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {Test, console} from "forge-std/Test.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dsce;
    HelperConfig config;
    address weth;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_COLLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;

    function setUp() public {
        deployer = new DeployDSC();
        (dsc, dsce, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, , ) = config
            .activeNetworkConfig();
        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    ///////////////////
    //test Price feed//
    //////////////////

    function testGetUSDValue() public {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dsce.getUSDValue(weth, ethAmount);
        assertEq(expectedUsd, actualUsd);
    }

    function testgetTokenAmountFromUsd() public {
        uint256 usdAmmount = 100e18;
        uint256 expectedeth = 0.05e18;
        uint256 actualEth = dsce.getTokenAmountFromUsd(weth, usdAmmount);
        assertEq(expectedeth, actualEth);
    }

    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dsce.depositeCollateral(weth, 0);
        vm.stopPrank();
    }

    address[] public tokenaddresses;
    address[] public pricefeeds;

    function testtokenaddressesAndPriceFeedsLength() public {
        tokenaddresses.push(weth);
        pricefeeds.push(ethUsdPriceFeed);
        pricefeeds.push(btcUsdPriceFeed);

        vm.expectRevert(
            DSCEngine
                .DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength
                .selector
        );

        new DSCEngine(tokenaddresses, pricefeeds, address(dsc));
    }

    function testDepositeCollateralIsNotAllowed() public {
        address dummyUser = makeAddr("dummyUser");
        vm.startPrank(dummyUser);
        vm.expectRevert(DSCEngine.DSCEngine__TokenNotAllowed.selector);
        dsce.depositeCollateral(dummyUser, AMOUNT_COLLATERAL);
    }

    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dsce), AMOUNT_COLLATERAL);
        dsce.depositeCollateral(weth, AMOUNT_COLLATERAL);
        vm.stopPrank();
        _;
    }

    function testDepositeCollateral() public depositedCollateral {
        (uint totalMinted, uint totalDepositeCollateral) = dsce.getUserACCInfo(
            USER
        );
        uint expectedMinted = 0;
        uint expectedDepositeAmount = dsce.getTokenAmountFromUsd(
            weth,
            totalDepositeCollateral
        );
        assertEq(totalMinted, expectedMinted);
        assertEq(expectedDepositeAmount, AMOUNT_COLLATERAL);
    }

    function test_revertIfHEalthFactorisBroken() public depositedCollateral {
        // Impersonate the owner to mint tokens
        vm.startPrank(address(dsce));
        dsc.mint(address(dsce), STARTING_ERC20_BALANCE);
        vm.expectRevert(DSCEngine.DSCEngine__HealthFactorBroken.selector);

        dsce.get_revertIfHEalthFactorisBroken(USER);

        vm.stopPrank();

        // Now simulate the user actions triggering the health factor check
    }
}
