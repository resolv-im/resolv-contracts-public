// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IUsrPriceStorage} from "./IUsrPriceStorage.sol";
import {IChainlinkOracle} from "./oracles/IChainlinkOracle.sol";
import {IDefaultErrors} from "./IDefaultErrors.sol";
import {ITreasury} from "./ITreasury.sol";

interface IUsrRedemptionExtension is IDefaultErrors {

    event TreasurySet(address _treasuryAddress);
    event ChainlinkOracleSet(address _chainlinkOracleAddress);
    event UsrPriceStorageSet(address _usrPriceStorageAddress);
    event UsrPriceStorageHeartbeatIntervalSet(uint256 _interval);
    event RedemptionLimitSet(uint256 _redemptionLimit);
    event AllowedWithdrawalTokenAdded(address _tokenAddress);
    event AllowedWithdrawalTokenRemoved(address _tokenAddres);
    event Redeemed(
        address indexed _sender,
        address indexed _receiver,
        uint256 _amount,
        address _withdrawalToken,
        uint256 _withdrawalTokenAmount
    );
    event RedemptionLimitReset(uint256 _newResetTime);

    error RedemptionLimitExceeded(uint256 _amount, uint256 _limit);
    error InvalidTokenAddress(address _token);
    error TokenAlreadyAllowed(address _token);
    error TokenNotAllowed(address _token);
    error InvalidLastResetTime(uint256 _lastResetTime);
    error UsrPriceHeartbeatIntervalCheckFailed();
    error InvalidUsrPrice(uint256 _price);

    function setTreasury(ITreasury _treasury) external;

    function setChainlinkOracle(IChainlinkOracle _chainlinkOracle) external;

    function setRedemptionLimit(uint256 _redemptionLimit) external;

    function setUsrPriceStorage(IUsrPriceStorage _usrPriceStorage) external;

    function setUsrPriceStorageHeartbeatInterval(uint256 _usrPriceStorageHeartbeatInterval) external;

    function addAllowedWithdrawalToken(address _allowedWithdrawalTokenAddress) external;

    function removeAllowedWithdrawalToken(address _allowedWithdrawalTokenAddress) external;

    function pause() external;

    function unpause() external;

    function redeem(
        uint256 _amount,
        address _receiver,
        address _withdrawalTokenAddress
    ) external returns (uint256 withdrawalTokenAmount);

    function redeem(uint256 _amount, address _withdrawalTokenAddress) external;

    function getRedeemPrice(address _withdrawalTokenAddress) external view returns (
        uint80 roundId,
        int256 price,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}
