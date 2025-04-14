// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/security/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "../lib/chainlink-brownie-contracts/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract DSCEngine is ReentrancyGuard {
    //////////////
    // Errors ///
    /////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken();
    error DSCEngine__MintedFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();
    /////////////////////////
    //   State Variables   //
    /////////////////////////
    uint private constant LIQUIDATION_THRESHOLD = 50;
    uint private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_BONUS = 10;
    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 ammount))
        private s_collateralDeposite;
    mapping(address => uint) private s_DSCMinted;
    address[] private s_CollateralValues;
    DecentralizedStableCoin private immutable s_dsc;

    //////////
    //event//
    /////////
    event CollateralDeposite(
        address indexed user,
        address indexed token,
        uint256 ammount
    );
    event CollateralRedeemed(
        address indexed redeemedFrom,
        address indexed redeemedTo,
        address indexed token,
        uint256 amount
    );

    //////////////
    // Modifiers//
    //////////////

    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__NeedsMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        if (s_priceFeeds[token] == address(0)) {
            revert DSCEngine__TokenNotAllowed();
        }
        _;
    }

    //////////////
    // Constructor//
    //////////////

    constructor(
        address[] memory _tokenAddresses,
        address[] memory _priceFeedAddresses,
        address dscAddress
    ) {
        if (_tokenAddresses.length != _priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            s_priceFeeds[_tokenAddresses[i]] = _priceFeedAddresses[i];
            s_CollateralValues.push(_tokenAddresses[i]);
        }

        s_dsc = DecentralizedStableCoin(dscAddress);
    }

    //////////////
    //External Functions//
    //////////////

    function depositeCollateralANdMntDSC(
        address _addressCollateral,
        uint256 _ammountCollateral,
        uint _ammountMint
    ) external {
        depositeCollateral(_addressCollateral, _ammountCollateral);
        mintDsc(_ammountMint);
    }

    function depositeCollateral(
        address _addressCollateral,
        uint256 _ammountCollateral
    )
        public
        moreThanZero(_ammountCollateral)
        isAllowedToken(_addressCollateral)
        nonReentrant
    {
        s_collateralDeposite[msg.sender][
            _addressCollateral
        ] += _ammountCollateral;
        emit CollateralDeposite(
            msg.sender,
            _addressCollateral,
            _ammountCollateral
        );
        bool success = IERC20(_addressCollateral).transferFrom(
            msg.sender,
            address(this),
            _ammountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDSC(
        address tokenCollateralAddress,
        uint256 amountCollateral,
        uint256 amountDscToBurn
    ) external {
        burnDSC(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
    }

    function redeemCollateral(
        address collateralTokenaddress,
        uint collateralAmount
    ) public moreThanZero(collateralAmount) nonReentrant {
        _redeemCollateral(
            msg.sender,
            msg.sender,
            collateralTokenaddress,
            collateralAmount
        );
        _revertIfHEalthFactorisBroken(msg.sender);
    }

    function mintDsc(uint _ammount) public moreThanZero(_ammount) nonReentrant {
        s_DSCMinted[msg.sender] += _ammount;
        _revertIfHEalthFactorisBroken(msg.sender);
        bool minted = s_dsc.mint(msg.sender, _ammount);
        if (!minted) {
            revert DSCEngine__MintedFailed();
        }
    }

    function burnDSC(uint amountBurn) public moreThanZero(amountBurn) {
        _burnDsc(amountBurn, msg.sender, msg.sender);
        _revertIfHEalthFactorisBroken(msg.sender);
    }

    function liquadiate(
        address collateral,
        address user,
        uint256 debtToCover
    ) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor > 1) {
            revert DSCEngine__HealthFactorOk();
        }

        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(
            collateral,
            debtToCover
        );

        uint256 bonusCollateral = (tokenAmountFromDebtCovered *
            LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralRedeemed = tokenAmountFromDebtCovered +
            bonusCollateral;
        _redeemCollateral(
            user,
            msg.sender,
            collateral,
            totalCollateralRedeemed
        );
        _burnDsc(debtToCover, user, msg.sender);
        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHEalthFactorisBroken(user);
    }

    function getTokenAmountFromUsd(
        address token,
        uint256 usdAmountInWei
    ) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();

        return (usdAmountInWei * PRECISION) / (uint256(price) * 1e10);
    }

    function getHealthFactor() external {}

    //////////////
    //Internal Functions//
    //////////////

    function _burnDsc(
        uint256 amountDscToBurn,
        address onBehalfOf,
        address dscFrom
    ) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;

        bool success = s_dsc.transferFrom(
            dscFrom,
            address(this),
            amountDscToBurn
        );
        // This conditional is hypothetically unreachable
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
        s_dsc.burn(amountDscToBurn);
    }

    function _redeemCollateral(
        address from,
        address to,
        address tokenCollateralAddress,
        uint256 amountCollateral
    ) private {
        s_collateralDeposite[from][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(
            from,
            to,
            tokenCollateralAddress,
            amountCollateral
        );

        bool success = IERC20(tokenCollateralAddress).transfer(
            to,
            amountCollateral
        );
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function _getUserAccInfo(address user) internal view returns (uint, uint) {
        uint totalMintedDSC = s_DSCMinted[user];
        uint totalCollateralDeposited = getAccountCollateralValue(user);
        return (totalMintedDSC, totalCollateralDeposited);
    }

    function _healthFactor(address user) internal view returns (uint) {
        //total dca minted
        //total colleteral minted
        (uint TotalDSCMinted, uint TotalCollateralDeposite) = _getUserAccInfo(
            user
        );
        uint CollateralAdjustForThreshold = (TotalCollateralDeposite *
            LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        return ((CollateralAdjustForThreshold * PRECISION) / TotalDSCMinted);
    }

    function _revertIfHEalthFactorisBroken(address _user) internal view {
        uint userHealthFactor = _healthFactor(_user);
        if (userHealthFactor < 1) {
            revert DSCEngine__HealthFactorBroken();
        }
    }

    function getAccountCollateralValue(
        address user
    ) public view returns (uint totalCollaeralValue) {
        for (uint i = 0; i < s_CollateralValues.length; i++) {
            address token = s_CollateralValues[i];
            uint ammount = s_collateralDeposite[user][token];
            totalCollaeralValue += getUSDValue(token, ammount);
        }

        return totalCollaeralValue;
    }

    function getUSDValue(
        address token,
        uint _ammount
    ) public view returns (uint) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(
            s_priceFeeds[token]
        );
        (, int256 price, , , ) = priceFeed.latestRoundData();
        return ((uint256(price * 1e10) * _ammount) / 1e18);
    }

    function getUserACCInfo(address user) external view returns (uint, uint) {
        (
            uint totalAmountMinted,
            uint totalCollateralDeposite
        ) = _getUserAccInfo(user);

        return (totalAmountMinted, totalCollateralDeposite);
    }

    function get_revertIfHEalthFactorisBroken(address user) external view {
        _revertIfHEalthFactorisBroken(user);
    }

    function getCollateralToken() external view returns (address[] memory) {
        return s_CollateralValues;
    }
}
