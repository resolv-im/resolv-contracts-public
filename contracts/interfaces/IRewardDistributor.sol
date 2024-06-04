// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";

interface IRewardDistributor is IDefaultErrors {

    event RewardDistributed(
        bytes32 indexed idempotencyKey,
        uint256 totalShares,
        uint256 totalUSRBefore,
        uint256 totalUSRAfter,
        uint256 stakingReward,
        uint256 feeReward
    );
    event FeeCollectorSet(address feeCollector);

    function distribute(bytes32 idempotencyKey, uint256 _stakingReward, uint256 _feeReward) external;

    function setFeeCollector(address _feeCollectorAddress) external;

    function pause() external;

    function unpause() external;

}
