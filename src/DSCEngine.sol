// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {nonReentrant} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
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

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
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
        getAccountCollateralValue(msg.sender);
    }

    function burnDSC() external {}

    function liquadiate() external {}

    function getHealthFactor() external {}

    //////////////
    //Internal Functions//
    //////////////

    function _getUserAccInfo(address user) internal view returns (uint, uint) {
        uint totalMintedDSC = s_DSCMinted[user];
    }

    function _healthFactor(address user) internal view {
        //total dca minted
        //total colleteral minted
        (uint TotalDSCMinted, uint TotalCollateralDeposite) = _getUserAccInfo(
            user
        );
    }

    function revertIfHEalthFactorisBroken(address _user) internal view {}

    function getAccountCollateralValue(
        address user
    ) public view returns (uint) {
        for (uint i = 0; i < s_CollateralValues.length; i++) {
            address token = s_CollateralValues[i];
            uint ammount = s_collateralDeposite[user][token];
        }
    }

    function getUSDValue(
        address user,
        uint _ammount
    ) public view returns (uint) {}
}
