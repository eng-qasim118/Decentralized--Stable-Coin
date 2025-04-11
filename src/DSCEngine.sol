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
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorBroken();
    error DSCEngine__MintedFailed();
    /////////////////////////
    //   State Variables   //
    /////////////////////////
    uint private constant LIQUIDATION_THRESHOLD = 50;
    uint private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;
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
            revert DSCEngine__TokenNotAllowed(token);
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

    function depositeCollateralANdMntDSC() external {}

    function depositeCollateral(
        address _addressCollateral,
        uint256 _ammountCollateral
    )
        external
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

    function redeemCollateralForDSC() external {}

    function redeemCollateral() external {}

    function mintDsc(
        uint _ammount
    ) external moreThanZero(_ammount) nonReentrant {
        s_DSCMinted[msg.sender] += _ammount;
        _revertIfHEalthFactorisBroken(msg.sender);
        bool minted = s_dsc.mint(msg.sender, _ammount);
        if (!minted) {
            revert DSCEngine__MintedFailed();
        }
    }

    function burnDSC() external {}

    function liquadiate() external {}

    function getHealthFactor() external {}

    //////////////
    //Internal Functions//
    //////////////

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
}
