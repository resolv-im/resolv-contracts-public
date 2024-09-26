// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title A FIFO queue for stETH withdrawal requests and an unstETH NFT implementation representing the position in the queue.
 * @dev For more details, see: https://docs.lido.fi/contracts/withdrawal-queue-erc721
*/
interface IWithdrawQueue {

    struct WithdrawalRequestStatus {
        uint256 amountOfStETH;
        uint256 amountOfShares;
        address owner;
        uint256 timestamp;
        bool isFinalized;
        bool isClaimed;
    }

    function requestWithdrawalsWstETH(
        uint256[] calldata _amounts,
        address _owner
    ) external returns (uint256[] memory requestIds);

    function findCheckpointHints(
        uint256[] calldata _requestIds,
        uint256 _firstIndex,
        uint256 _lastIndex
    ) external view returns (uint256[] memory hintIds);

    function getLastCheckpointIndex() external view returns (uint256 lastCheckpointIndex);

    function claimWithdrawalsTo(uint256[] calldata _requestIds, uint256[] calldata _hints, address _recipient) external;

    function getWithdrawalStatus(
        uint256[] calldata _requestIds
    ) external view returns (WithdrawalRequestStatus[] memory statuses);

    function finalize(uint256 _lastRequestIdToBeFinalized, uint256 _maxShareRate) external payable;

    function getLastRequestId() external view returns (uint256 lastRequestId);

    function getLastFinalizedRequestId() external view returns (uint256 lastFinalizedRequestId);

    function unfinalizedStETH() external view returns (uint256 unfinalizedStETH);

    function balanceOf(address _owner) external view returns (uint256 balance);
}
