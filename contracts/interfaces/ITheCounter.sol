// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITheCounter is IDefaultErrors {

    enum State {CREATED, COMPLETED, CANCELLED}

    struct Request {
        uint256 id;
        uint256 amount;
        uint256 minExpectedAmount;
        address provider;
        address token;
        State state;
    }

    event SwapRequestCreated(
        uint256 indexed id,
        address indexed provider,
        address depositToken,
        uint256 amount,
        uint256 minSwapAmount
    );
    event SwapRequestCompleted(bytes32 indexed idempotencyKey, uint256 indexed id, uint256 swappedAmount, uint256 takenFee);
    event SwapRequestCancelled(uint256 indexed id);
    event TreasurySet(address treasuryAddress);
    event EmergencyWithdrawn(address tokenAddress, uint256 amount);
    event FeeSet(uint256 fee);
    event FeeTransferred(uint256 amount);
    event MinimumSwapAmountSet(address requestedTokenAddress, uint256 newAmount);
    event AllowedTokenAdded(address tokenAddress);
    event AllowedTokenRemoved(address tokenAddres);

    error IllegalState(State expected, State current);
    error IllegalAddress(address expected, address actual);
    error InvalidTokenAddress(address token);
    error SwapRequestNotExist(uint256 id);
    error InsufficientAmount(uint256 amount, uint256 minAmount);
    error AddressIsNotContract(address actual);
    error FeeMoreThanMaxFee(uint256 fee, uint256 maxFee);
    error IllegalMinSwapParameters(address[] tokens, uint256[] minSwapAmounts);
    error TokenIsNotSupported(address _tokenAddress);
    error ZeroFee();
    error TokenNotAllowed(address token);

    function setTreasury(address _treasuryAddress) external;

    function pause() external;

    function unpause() external;

    function emergencyWithdraw(IERC20 _token) external;

    function requestSwap(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minSwapAmount
    ) external;

    function requestSwapWithPermit(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minSwapAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external;

    function cancelSwap(uint256 _id) external;

    function completeSwap(bytes32 _idempotencyKey, uint256 _id, uint256 _targetAmount) external;

    /**
    * Set the contract's fee in one million part (1 / 10 ^ 6). Note, that the fee will be get from swapped tokens.
    *
    * @param _feePart part of tokens that this contract will get as a fee. It must be below 100000 - meaning 1 / 10.
    */
    function setFee(uint256 _feePart) external;

    function transferFee() external;

    function setMinSwapAmount(address requestedTokenAddress, uint256 newAmount) external;

    function addAllowedToken(address _allowedTokenAddress, uint256 _minSwapAmount) external;

    function removeAllowedToken(address _allowedTokenAddress) external;
}
