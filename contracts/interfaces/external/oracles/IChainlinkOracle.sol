// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IChainlinkOracle {

    event HeartbeatIntervalSet(address indexed tokenAddress, uint48 heartbeatInterval);
    event FeedRegistrySet(address indexed feedRegistry);

    error ChainlinkOracleHeartbeatFailed();
    error InvalidArrayLengths();

    function setHeartbeatInterval(address _tokenAddress, uint48 _heartbeatInterval) external;

    function getPrice(address _tokenAddress) external view returns (uint256 price);

    function getLatestRoundData(address _tokenAddress) external view returns (
        uint80 roundId,
        int256 price,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );

    function priceDecimals(address _tokenAddress) external view returns (uint8 decimals);

    function quoteCurrency() external view returns (address currency);
}
