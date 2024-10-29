// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITreasury is IDefaultErrors {

    event Received(address indexed _from, uint256 _amount);
    event OperationLimitSet(OperationType _operation, uint256 _limit);
    event TransferredETH(bytes32 indexed _idempotencyKey, address indexed _to, uint256 _amount);
    event TransferredERC20(bytes32 indexed _idempotencyKey, address indexed _token, address indexed _to, uint256 _amount);
    event IncreasedAllowance(bytes32 indexed _idempotencyKey, address indexed _token, address indexed _spender, uint256 _increaseAmount);
    event DecreasedAllowance(bytes32 indexed _idempotencyKey, address indexed _token, address indexed _spender, uint256 _decreaseAmount);
    event RecipientWhitelistSet(address indexed recipientWhitelist);
    event SpenderWhitelistSet(address indexed spenderWhitelist);
    event RecipientWhitelistEnabledSet(bool isEnabled);
    event SpenderWhitelistEnabledSet(bool isEnabled);
    event LidoDeposited(bytes32 indexed _idempotencyKey, uint256 _amount, uint256 _wstETHAmount);
    event LidoWithdrawalsRequested(bytes32 indexed _idempotencyKey, uint256[] _requestIds, uint256[] _amounts, uint256 _totalAmount);
    event LidoWithdrawalsClaimed(bytes32 indexed _idempotencyKey, uint256[] _requestIds);
    event LidoTreasuryConnectorSet(address indexed _lidoTreasuryConnector);
    event LidoReferralCodeSet(address indexed _lidoReferralCode);
    event AaveSupplied(bytes32 indexed _idempotencyKey, address indexed _token, uint256 _amount);
    event AaveBorrowed(bytes32 indexed _idempotencyKey, address indexed _token, uint256 _amount, uint256 _rateMode);
    event AaveRepaid(bytes32 indexed _idempotencyKey, address indexed _token, uint256 _amount, uint256 _rateMode);
    event AaveWithdrawn(bytes32 indexed _idempotencyKey, address indexed _token, uint256 _amount);
    event AaveReferralCodeSet(uint16 _aaveReferralCode);
    event AaveTreasuryConnectorSet(address indexed _aaveTreasuryConnector);
    event DineroDeposited(bytes32 indexed _idempotencyKey, uint256 _amount, uint256 _pxETHPostFeeAmount, uint256 _feeAmount, uint256 _apxETHAmount);
    event DineroInitiatedRedemption(bytes32 indexed _idempotencyKey, uint256 _apxETHAmount, uint256 _pxETHPostFeeAmount, uint256 _feeAmount);
    event DineroInstantRedeemed(bytes32 indexed _idempotencyKey, uint256 _apxETHAmount, uint256 _pxETHPostFeeAmount, uint256 _feeAmount);
    event DineroRedeemed(bytes32 indexed _idempotencyKey, uint256[] _upxETHTokenIds);
    event DineroTreasuryConnectorSet(address indexed _dineroTreasuryConnector);

    error InsufficientFunds();
    error OperationLimitExceeded(OperationType _operation, uint256 _amount);
    error UnknownRecipient(address _recipient);
    error UnknownSpender(address _spender);
    error InvalidRecipientWhitelist(address _recipientWhitelist);
    error InvalidSpenderWhitelist(address _spenderWhitelist);
    error InvalidLidoTreasuryConnector(address _lidoTreasuryConnector);
    error InvalidAaveTreasuryConnector(address _aaveTreasuryConnector);
    error InvalidDineroTreasuryConnector(address _dineroTreasuryConnector);

    enum OperationType {
        LidoDeposit,
        LidoRequestWithdrawals,
        LidoClaimWithdrawals,
        AaveSupply,
        AaveBorrow,
        AaveWithdraw,
        AaveRepay,
        TransferETH,
        TransferERC20,
        IncreaseAllowance,
        DecreaseAllowance,
        DineroDeposit,
        DineroInitiateRedemption,
        DineroInstantRedeem,
        DineroRedeem
    }

    function setOperationLimit(
        OperationType _operation,
        uint256 _limit
    ) external;

    function setRecipientWhitelist(address _recipientWhitelist) external;

    function setRecipientWhitelistEnabled(bool _isEnabled) external;

    function setSpenderWhitelistEnabled(bool _isEnabled) external;

    function setSpenderWhitelist(address _spenderWhitelist) external;

    function pause() external;

    function unpause() external;

    function transferETH(
        bytes32 _idempotencyKey,
        address payable _to,
        uint256 _amount
    ) external;

    function transferERC20(
        bytes32 _idempotencyKey,
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function increaseAllowance(
        bytes32 _idempotencyKey,
        IERC20 _token,
        address _spender,
        uint256 _increaseAmount
    ) external;

    function decreaseAllowance(
        bytes32 _idempotencyKey,
        IERC20 _token,
        address _spender,
        uint256 _decreaseAmount
    ) external;

    function lidoDeposit(
        bytes32 _idempotencyKey,
        uint256 _amount
    ) external returns (uint256 wstETHAmount);

    function lidoRequestWithdrawals(
        bytes32 _idempotencyKey,
        uint256[] calldata _amounts
    ) external returns (uint256[] memory requestIds);

    function lidoClaimWithdrawals(
        bytes32 _idempotencyKey,
        uint256[] calldata _requestIds
    ) external;

    function setLidoTreasuryConnector(
        address _lidoTreasuryConnector
    ) external;

    function setLidoReferralCode(
        address _lidoReferralCode
    ) external;

    function aaveSupply(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _supplyAmount
    ) external;

    function aaveBorrow(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _borrowAmount,
        uint256 _rateMode
    ) external;

    function aaveSupplyAndBorrow(
        bytes32 _idempotencyKey,
        address _supplyToken,
        uint256 _supplyAmount,
        address _borrowToken,
        uint256 _borrowAmount,
        uint256 _rateMode
    ) external;

    function aaveRepay(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _repayAmount,
        uint256 _rateMode
    ) external;

    function aaveWithdraw(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _withdrawAmount
    ) external;

    function aaveRepayAndWithdraw(
        bytes32 _idempotencyKey,
        address _repayToken,
        uint256 _repayAmount,
        address _withdrawToken,
        uint256 _withdrawAmount,
        uint256 _rateMode
    ) external;

    function setAaveTreasuryConnector(
        address _aaveTreasuryConnector
    ) external;

    function setAaveReferralCode(
        uint16 _aaveReferralCode
    ) external;

    function dineroDeposit(
        bytes32 _idempotencyKey,
        uint256 _amount
    ) external returns (uint256 pxETHPostFeeAmount, uint256 feeAmount, uint256 apxETHAmount);

    function dineroInitiateRedemption(
        bytes32 _idempotencyKey,
        uint256 _apxETHAmount
    ) external returns (uint256 pxETHPostFeeAmount, uint256 feeAmount);

    function dineroInstantRedeemWithApxEth(
        bytes32 _idempotencyKey,
        uint256 _apxETHAmount
    ) external returns (uint256 pxETHPostFeeAmount, uint256 feeAmount);

    function dineroRedeem(
        bytes32 _idempotencyKey,
        uint256[] calldata _upxETHTokenIds
    ) external;
}
