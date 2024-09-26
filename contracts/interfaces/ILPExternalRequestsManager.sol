// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILPExternalRequestsManager is IDefaultErrors {

    event MintRequestCreated(
        uint256 indexed id,
        address indexed provider,
        address depositToken,
        uint256 amount,
        uint256 minMintAmount
    );
    event MintRequestCompleted(bytes32 indexed idempotencyKey, uint256 indexed id, uint256 mintedAmount);
    event MintRequestCancelled(uint256 indexed id);

    event BurnRequestCreated(
        uint256 indexed id,
        address indexed provider,
        address withdrawalTokenAddress,
        uint256 requestedToBurnAmount
    );
    event BurnRequestProcessing(bytes32 indexed idempotencyKey, uint256 indexed id, uint256 indexed epochId);
    event BurnRequestsEpochProcessing(uint256 indexed id);
    event BurnRequestUnprocessed(bytes32 indexed idempotencyKey, uint256 indexed id, uint256 indexed epochId);
    event BurnRequestsEpochUnprocessed(uint256 indexed id);
    event BurnRequestCompleted(
        bytes32 indexed idempotencyKey,
        uint256 indexed id,
        uint256 indexed epochId,
        uint256 burnedAmount,
        uint256 withdrawalCollateralAmount
    );
    event BurnRequestPartiallyCompleted(
        bytes32 indexed idempotencyKey,
        uint256 indexed id,
        uint256 indexed epochId,
        uint256 burnedAmount,
        uint256 withdrawalCollateralAmount,
        uint256 remainingAmount
    );
    event BurnRequestsEpochCompleted(
        bytes32 indexed idempotencyKey,
        uint256 indexed epochId,
        uint256 totalBurnedAmount,
        uint256[] totalWithdrawalCollateralAmounts
    );
    event BurnRequestCancelled(uint256 indexed id);
    event AvailableCollateralWithdrawn(uint256 indexed id, uint256 amount);

    event TreasurySet(address treasuryAddress);
    event ProvidersWhitelistSet(address providersWhitelistAddress);
    event WhitelistEnabledSet(bool isEnabled);
    event BurnRequestsPerEpochLimitSet(uint256 limit);
    event AllowedTokenAdded(address tokenAddress);
    event AllowedTokenRemoved(address tokenAddres);
    event EmergencyWithdrawn(address tokenAddress, uint256 amount);

    error UnknownProvider(address account);
    error IllegalState(uint256 current);
    error IllegalAddress(address expected, address actual);
    error MintRequestNotExist(uint256 id);
    error BurnRequestNotExist(uint256 id);
    error BurnRequestPreviousEpochIsActive(uint256 epochId);
    error BurnRequestCurrentEpochIsNotActive(uint256 epochId);
    error BurnRequestsLimitExceeded(uint256 limit, uint256 actual);
    error InvalidBurnRequestsLength(uint256 exepcted, uint256 actual);
    error WithdrawalTokenNotFound(address withdrawalToken);
    error TokenNotAllowed(address token);
    error InvalidProvidersWhitelist(address providersWhitelistAddress);
    error InvalidTokenAddress(address token);
    error InsufficientMintAmount(uint256 mintAmount, uint256 minMintAmount);

    enum MintRequestState {CREATED, COMPLETED, CANCELLED}
    enum BurnRequestState {CREATED, PROCESSING, PARTIALLY_COMPLETED, COMPLETED, CANCELLED}

    struct MintRequest {
        uint256 id;
        address provider;
        MintRequestState state;
        uint256 amount;
        address token;
        uint256 minExpectedAmount;
    }

    struct BurnRequest {
        uint256 id;
        address provider;
        BurnRequestState state;
        address token;
        uint256 requestedToBurnAmount;
        uint256 burnedAmount;
        uint256 withdrawalCollateralAmount;
    }

    struct Epoch {
        bool isActive;
        uint256[] burnRequestIds;
    }

    struct CompleteBurnItem {
        uint256 id;
        address withdrawalToken;
        uint256 burnAmount;
        uint256 withdrawalCollateralAmount;
    }

    function setTreasury(address _treasuryAddress) external;

    function setProvidersWhitelist(address _providersWhitelistAddress) external;

    function setWhitelistEnabled(bool _isEnabled) external;

    function setBurnRequestsPerEpochLimit(uint256 _burnRequestsPerEpochLimit) external;

    function addAllowedToken(address _allowedTokenAddress) external;

    function removeAllowedToken(address _allowedTokenAddress) external;

    function pause() external;

    function unpause() external;

    function requestMint(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minMintAmount
    ) external;

    function requestMintWithPermit(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minMintAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function cancelMint(uint256 _id) external;

    function completeMint(bytes32 _idempotencyKey, uint256 _id, uint256 _mintAmount) external;

    function requestBurn(
        address _withdrawalTokenAddress,
        uint256 _amount
    ) external;

    function requestBurnWithPermit(
        address _withdrawalTokenAddress,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function processBurns(
        bytes32 _idempotencyKey,
        uint256[] calldata _ids
    ) external;

    function unprocessCurrentBurnEpoch(
        bytes32 _idempotencyKey
    ) external;

    function getEpoch(uint256 _epochId) external view returns (Epoch memory epoch);

    function completeBurns(
        bytes32 _idempotencyKey,
        CompleteBurnItem[] calldata _items,
        address[] calldata _withdrawalTokens
    ) external;


    function cancelBurn(uint256 _id) external;

    function withdrawAvailableCollateral(uint256 _id) external;

    function emergencyWithdraw(IERC20 _token) external;
}
