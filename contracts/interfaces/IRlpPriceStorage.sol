// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IRlpPriceStorage {

    struct Price {
        uint256 price;
        uint256 timestamp;
    }

    event PriceSet(bytes32 indexed key, uint256 price, uint256 timestamp);
    event UpperBoundPercentageSet(uint256 upperBoundPercentage);
    event LowerBoundPercentageSet(uint256 lowerBoundPercentage);

    error PriceAlreadySet(bytes32 distributionTxHash);
    error InvalidPrice();
    error InvalidKey();
    error InvalidUpperBoundPercentage();
    error InvalidLowerBoundPercentage();
    error InvalidPriceRange(uint256 price, uint256 lowerBound, uint256 upperBound);

    function setPrice(bytes32 _key, uint256 _price) external;

    function setUpperBoundPercentage(uint256 _upperBoundPercentage) external;

    function setLowerBoundPercentage(uint256 _lowerBoundPercentage) external;

    function lastPrice() external view returns (uint256 price, uint256 timestamp);

    function prices(bytes32 _key) external view returns (uint256 price, uint256 timestamp);
}
