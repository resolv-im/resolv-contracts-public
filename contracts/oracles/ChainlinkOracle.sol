// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Denominations} from "@chainlink/contracts/src/v0.8/Denominations.sol";
import {FeedRegistryInterface} from "@chainlink/contracts/src/v0.8/interfaces/FeedRegistryInterface.sol";
import {IChainlinkOracle} from "../interfaces/oracles/IChainlinkOracle.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {IDefaultErrors} from "../interfaces/IDefaultErrors.sol";

contract ChainlinkOracle is IChainlinkOracle, IDefaultErrors, Ownable2Step {

    FeedRegistryInterface public feedRegistry;
    mapping(address token => uint48 heartbeatInterval) public tokenHeartbeatIntervals;

    // slither-disable-start pess-strange-setter
    constructor(
        FeedRegistryInterface _feedRegistry,
        address[] memory _tokenAddresses,
        uint48[] memory _heartbeatIntervals
    ) Ownable(msg.sender) {
        setFeedRegistry(_feedRegistry);
        if (_tokenAddresses.length != _heartbeatIntervals.length) revert InvalidArrayLengths();
        for (uint256 i = 0; i < _tokenAddresses.length; i++) {
            setHeartbeatInterval(_tokenAddresses[i], _heartbeatIntervals[i]);
        }
    }
    // slither-disable-end pess-strange-setter

    function getPrice(address _tokenAddress) external view returns (uint256 price) {
        (, int256 latestRoundPrice,,,) = getLatestRoundData(_tokenAddress);
        return SafeCast.toUint256(latestRoundPrice);
    }

    function priceDecimals(address _tokenAddress) external view returns (uint8 decimals) {
        return feedRegistry.decimals(_tokenAddress, Denominations.USD);
    }

    function quoteCurrency() external pure returns (address currency) {
        return Denominations.USD;
    }

    function setFeedRegistry(FeedRegistryInterface _feedRegistry) public onlyOwner {
        if (address(_feedRegistry) == address(0)) revert ZeroAddress();
        feedRegistry = _feedRegistry;
        emit FeedRegistrySet(address(_feedRegistry));
    }

    function setHeartbeatInterval(address _tokenAddress, uint48 _heartbeatInterval) public onlyOwner {
        if (_tokenAddress == address(0)) revert ZeroAddress();
        tokenHeartbeatIntervals[_tokenAddress] = _heartbeatInterval;
        emit HeartbeatIntervalSet(_tokenAddress, _heartbeatInterval);
    }

    function getLatestRoundData(address _tokenAddress) public view returns (
        uint80 roundId,
        int256 price,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        (
            roundId,
            price,
            startedAt,
            updatedAt,
            answeredInRound
        ) = feedRegistry.latestRoundData(_tokenAddress, Denominations.USD);

        uint48 heartbeatInterval = tokenHeartbeatIntervals[_tokenAddress];
        if (block.timestamp - updatedAt > heartbeatInterval) revert ChainlinkOracleHeartbeatFailed();

        return (roundId, price, startedAt, updatedAt, answeredInRound);
    }

}
