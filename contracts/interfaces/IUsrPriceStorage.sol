// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IUsrPriceStorage {

    struct Price {
        uint256 price;
        uint256 usrSupply;
        uint256 reserves;
        uint256 timestamp;
    }

    event PriceSet(bytes32 indexed key, uint256 price, uint256 usrSupply, uint256 reserves, uint256 timestamp);
    event LowerBoundPercentageSet(uint256 lowerBoundPercentage);

    error InvalidKey();
    error InvalidUsrSupply();
    error InvalidReserves();
    error PriceAlreadySet(bytes32 key);
    error InvalidLowerBoundPercentage();
    error InvalidPrice(uint256 price, uint256 lowerBound);

    function setReserves(
        bytes32 _key,
        uint256 usrSupply,
        uint256 reserves
    ) external;

    function setLowerBoundPercentage(uint256 _lowerBoundPercentage) external;

    function lastPrice() external view returns (
        uint256 price,
        uint256 usrSupply,
        uint256 reserves,
        uint256 timestamp
    );

    function prices(bytes32 key) external view returns (
        uint256 price,
        uint256 usrSupply,
        uint256 reserves,
        uint256 timestamp
    );

    // solhint-disable-next-line style-guide-casing
    function PRICE_SCALING_FACTOR() external view returns (uint256 scale);

}
