// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DSCEngine is ReentrancyGuard {
    //////////////
    // Errors ///
    /////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__TokenNotAllowed(address token);
    error DSCEngine__TransferFailed();
    /////////////////////////
    //   State Variables   //
    /////////////////////////

    mapping(address token => address priceFeed) private s_priceFeeds;
    mapping(address user => mapping(address token => uint256 ammount))
        private s_collateralDeposite;
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

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
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

    function mintDsc(uint _ammount) external moreThanZero(_ammount) {}

    function burnDSC() external {}

    function liquadiate() external {}

    function getHealthFactor() external {}
}
