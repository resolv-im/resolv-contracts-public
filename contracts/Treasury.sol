// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ILidoTreasuryConnector} from "./interfaces/ILidoTreasuryConnector.sol";
import {IAaveTreasuryConnector} from "./interfaces/IAaveTreasuryConnector.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IAddressesWhitelist} from "./interfaces/IAddressesWhitelist.sol";
import {IDineroTreasuryConnector} from "./interfaces/IDineroTreasuryConnector.sol";

contract Treasury is ITreasury, AccessControlDefaultAdminRulesUpgradeable, PausableUpgradeable {

    using Address for address payable;
    using SafeERC20 for IERC20;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    IERC20 public constant WST_ETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    IERC20 public constant APX_ETH = IERC20(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6);

    address public lidoReferralCode;
    ILidoTreasuryConnector public lidoTreasuryConnector;

    uint16 public aaveReferralCode;
    IAaveTreasuryConnector public aaveTreasuryConnector;

    IDineroTreasuryConnector public dineroTreasuryConnector;

    IAddressesWhitelist public recipientWhitelist;
    bool public isRecipientWhitelistEnabled;

    IAddressesWhitelist public spenderWhitelist;
    bool public isSpenderWhitelistEnabled;

    mapping(OperationType operation => mapping(bytes32 idempotencyKey => bool exist)) public operationRegistry;
    mapping(OperationType operation => uint256 limit) public operationLimits;

    modifier idempotent(OperationType _operation, bytes32 _idempotencyKey) {
        if (operationRegistry[_operation][_idempotencyKey]) {
            revert IdempotencyKeyAlreadyExist(_idempotencyKey);
        }
        _;
        operationRegistry[_operation][_idempotencyKey] = true;
    }

    modifier onlyAllowedRecipient(address _recipient) {
        if (isRecipientWhitelistEnabled && !recipientWhitelist.isAllowedAccount(_recipient)) {
            revert UnknownRecipient(_recipient);
        }
        _;
    }

    modifier onlyAllowedSpender(address _spender) {
        if (isSpenderWhitelistEnabled && !spenderWhitelist.isAllowedAccount(_spender)) {
            revert UnknownSpender(_spender);
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _lidoTreasuryConnector,
        address _aaveTreasuryConnector,
        address _dineroTreasuryConnector,
        address _recipientWhitelist,
        address _spenderWhitelist
    ) public initializer {
        __AccessControlDefaultAdminRules_init(1 days, msg.sender);
        __Pausable_init();

        operationLimits[OperationType.LidoDeposit] = type(uint256).max;
        operationLimits[OperationType.LidoRequestWithdrawals] = type(uint256).max;
        operationLimits[OperationType.AaveSupply] = type(uint256).max;
        operationLimits[OperationType.AaveBorrow] = type(uint256).max;
        operationLimits[OperationType.AaveWithdraw] = type(uint256).max;
        operationLimits[OperationType.AaveRepay] = type(uint256).max;
        operationLimits[OperationType.TransferETH] = type(uint256).max;
        operationLimits[OperationType.TransferERC20] = type(uint256).max;
        operationLimits[OperationType.IncreaseAllowance] = type(uint256).max;
        operationLimits[OperationType.DecreaseAllowance] = type(uint256).max;
        operationLimits[OperationType.DineroDeposit] = type(uint256).max;
        operationLimits[OperationType.DineroInitiateRedemption] = type(uint256).max;
        operationLimits[OperationType.DineroInstantRedeem] = type(uint256).max;

        _assertNonZero(_lidoTreasuryConnector);
        lidoTreasuryConnector = ILidoTreasuryConnector(_lidoTreasuryConnector);
        lidoReferralCode = address(0);

        _assertNonZero(_aaveTreasuryConnector);
        aaveTreasuryConnector = IAaveTreasuryConnector(_aaveTreasuryConnector);
        aaveReferralCode = 0;

        _assertNonZero(_dineroTreasuryConnector);
        dineroTreasuryConnector = IDineroTreasuryConnector(_dineroTreasuryConnector);

        _assertNonZero(_recipientWhitelist);
        recipientWhitelist = IAddressesWhitelist(_recipientWhitelist);
        isRecipientWhitelistEnabled = true;

        _assertNonZero(_spenderWhitelist);
        spenderWhitelist = IAddressesWhitelist(_spenderWhitelist);
        isSpenderWhitelistEnabled = true;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function setOperationLimit(
        OperationType _operation,
        uint256 _limit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        operationLimits[_operation] = _limit;

        emit OperationLimitSet(_operation, _limit);
    }

    function setRecipientWhitelistEnabled(bool _isEnabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isRecipientWhitelistEnabled = _isEnabled;

        emit RecipientWhitelistEnabledSet(_isEnabled);
    }

    function setRecipientWhitelist(address _recipientWhitelist) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_recipientWhitelist);
        if (_recipientWhitelist.code.length == 0) revert InvalidRecipientWhitelist(_recipientWhitelist);

        recipientWhitelist = IAddressesWhitelist(_recipientWhitelist);

        emit RecipientWhitelistSet(_recipientWhitelist);
    }

    function setSpenderWhitelistEnabled(bool _isEnabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isSpenderWhitelistEnabled = _isEnabled;

        emit SpenderWhitelistEnabledSet(_isEnabled);
    }

    function setSpenderWhitelist(address _spenderWhitelist) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_spenderWhitelist);
        if (_spenderWhitelist.code.length == 0) revert InvalidSpenderWhitelist(_spenderWhitelist);

        spenderWhitelist = IAddressesWhitelist(_spenderWhitelist);

        emit SpenderWhitelistSet(_spenderWhitelist);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    function transferETH(
        bytes32 _idempotencyKey,
        address payable _to,
        uint256 _amount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.TransferETH, _idempotencyKey) onlyAllowedRecipient(_to) {
        if (paused()) {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }

        _assertNonZero(_to);
        _assertNonZero(_amount);
        _assertSufficientFunds(_amount);
        _assertOperationLimit(OperationType.TransferETH, _amount);

        _to.sendValue(_amount);

        emit TransferredETH(_idempotencyKey, _to, _amount);
    }

    function transferERC20(
        bytes32 _idempotencyKey,
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.TransferERC20, _idempotencyKey) onlyAllowedRecipient(_to) {
        if (paused()) {
            _checkRole(DEFAULT_ADMIN_ROLE);
        }

        _assertNonZero(address(_token));
        _assertNonZero(_to);
        _assertNonZero(_amount);
        _assertOperationLimit(OperationType.TransferERC20, _amount);

        _token.safeTransfer(_to, _amount);

        emit TransferredERC20(_idempotencyKey, address(_token), _to, _amount);
    }

    function increaseAllowance(
        bytes32 _idempotencyKey,
        IERC20 _token,
        address _spender,
        uint256 _increaseAmount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.IncreaseAllowance, _idempotencyKey) onlyAllowedSpender(_spender) whenNotPaused {
        _assertNonZero(address(_token));
        _assertNonZero(_spender);
        _assertNonZero(_increaseAmount);
        _assertOperationLimit(OperationType.IncreaseAllowance, _increaseAmount);

        _token.safeIncreaseAllowance(_spender, _increaseAmount);

        emit IncreasedAllowance(_idempotencyKey, address(_token), _spender, _increaseAmount);
    }

    function decreaseAllowance(
        bytes32 _idempotencyKey,
        IERC20 _token,
        address _spender,
        uint256 _decreaseAmount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.DecreaseAllowance, _idempotencyKey) whenNotPaused {
        _assertNonZero(address(_token));
        _assertNonZero(_spender);
        _assertNonZero(_decreaseAmount);
        _assertOperationLimit(OperationType.DecreaseAllowance, _decreaseAmount);

        _token.safeDecreaseAllowance(_spender, _decreaseAmount);

        emit DecreasedAllowance(_idempotencyKey, address(_token), _spender, _decreaseAmount);
    }

    function lidoDeposit(
        bytes32 _idempotencyKey,
        uint256 _amount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.LidoDeposit, _idempotencyKey) whenNotPaused returns (uint256 wstETHAmount) {
        _assertNonZero(_amount);
        _assertSufficientFunds(_amount);
        _assertOperationLimit(OperationType.LidoDeposit, _amount);

        // slither-disable-next-line arbitrary-send-eth
        wstETHAmount = lidoTreasuryConnector.deposit{value: _amount}(lidoReferralCode);

        emit LidoDeposited(_idempotencyKey, _amount, wstETHAmount);

        return wstETHAmount;
    }

    function lidoRequestWithdrawals(
        bytes32 _idempotencyKey,
        uint256[] calldata _amounts
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.LidoRequestWithdrawals, _idempotencyKey) whenNotPaused returns (uint256[] memory requestIds) {
        uint256 totalAmount;
        for (uint256 i = 0; i < _amounts.length; i++) {
            _assertNonZero(_amounts[i]);
            totalAmount += _amounts[i];
        }

        _assertNonZero(totalAmount);
        _assertOperationLimit(OperationType.LidoRequestWithdrawals, totalAmount);

        WST_ETH.safeIncreaseAllowance(address(lidoTreasuryConnector), totalAmount);

        requestIds = lidoTreasuryConnector.requestWithdrawals(_amounts, totalAmount);

        emit LidoWithdrawalsRequested(_idempotencyKey, requestIds, _amounts, totalAmount);
    }

    function lidoClaimWithdrawals(
        bytes32 _idempotencyKey,
        uint256[] calldata _requestIds
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.LidoClaimWithdrawals, _idempotencyKey) whenNotPaused {
        lidoTreasuryConnector.claimWithdrawals(_requestIds);

        emit LidoWithdrawalsClaimed(_idempotencyKey, _requestIds);
    }

    function setLidoTreasuryConnector(
        address _lidoTreasuryConnector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_lidoTreasuryConnector);
        if (_lidoTreasuryConnector.code.length == 0) revert InvalidLidoTreasuryConnector(_lidoTreasuryConnector);

        lidoTreasuryConnector = ILidoTreasuryConnector(_lidoTreasuryConnector);

        emit LidoTreasuryConnectorSet(_lidoTreasuryConnector);
    }

    function setLidoReferralCode(
        address _lidoReferralCode
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lidoReferralCode = _lidoReferralCode;

        emit LidoReferralCodeSet(_lidoReferralCode);
    }

    function aaveSupply(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _supplyAmount
    ) public onlyRole(SERVICE_ROLE) idempotent(OperationType.AaveSupply, _idempotencyKey) whenNotPaused {
        _assertNonZero(_token);
        _assertNonZero(_supplyAmount);
        _assertOperationLimit(OperationType.AaveSupply, _supplyAmount);

        IAaveTreasuryConnector connector = aaveTreasuryConnector;

        if (connector.isETH(_token)) {
            _assertSufficientFunds(_supplyAmount);
            connector.supply{value: _supplyAmount}(_token, _supplyAmount, aaveReferralCode);
        } else {
            IERC20(_token).safeIncreaseAllowance(address(connector), _supplyAmount);
            connector.supply(_token, _supplyAmount, aaveReferralCode);
        }

        emit AaveSupplied(_idempotencyKey, _token, _supplyAmount);
    }

    function aaveBorrow(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _borrowAmount,
        uint256 _rateMode
    ) public onlyRole(SERVICE_ROLE) idempotent(OperationType.AaveBorrow, _idempotencyKey) whenNotPaused {
        _assertNonZero(_token);
        _assertNonZero(_borrowAmount);
        _assertOperationLimit(OperationType.AaveBorrow, _borrowAmount);

        IAaveTreasuryConnector connector = aaveTreasuryConnector;
        connector.borrow(_token, _borrowAmount, _rateMode, aaveReferralCode);

        emit AaveBorrowed(_idempotencyKey, _token, _borrowAmount, _rateMode);
    }

    function aaveSupplyAndBorrow(
        bytes32 _idempotencyKey,
        address _supplyToken,
        uint256 _supplyAmount,
        address _borrowToken,
        uint256 _borrowAmount,
        uint256 _rateMode
    ) external onlyRole(SERVICE_ROLE) whenNotPaused {
        aaveSupply(_idempotencyKey, _supplyToken, _supplyAmount);
        aaveBorrow(_idempotencyKey, _borrowToken, _borrowAmount, _rateMode);
    }

    /**
    * @param _repayAmount Use `type(uint256).max` to withdraw the maximum available amount.
    */
    function aaveRepay(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _repayAmount,
        uint256 _rateMode
    ) public onlyRole(SERVICE_ROLE) idempotent(OperationType.AaveRepay, _idempotencyKey) whenNotPaused {
        _assertNonZero(_token);
        _assertNonZero(_repayAmount);
        _assertOperationLimit(OperationType.AaveRepay, _repayAmount);

        IAaveTreasuryConnector connector = aaveTreasuryConnector;

        if (connector.isETH(_token)) {
            if (_repayAmount == type(uint256).max) {
                _repayAmount = connector.getCurrentDebt(
                    connector.getWETHAddress(),
                    _rateMode
                );
            }
            _assertSufficientFunds(_repayAmount);
            connector.repay{value: _repayAmount}(_token, _repayAmount, _rateMode);
        } else {
            if (_repayAmount == type(uint256).max) {
                _repayAmount = connector.getCurrentDebt(
                    _token,
                    _rateMode
                );
            }
            IERC20(_token).safeIncreaseAllowance(address(connector), _repayAmount);
            connector.repay(_token, _repayAmount, _rateMode);
        }

        emit AaveRepaid(_idempotencyKey, _token, _repayAmount, _rateMode);
    }

    /**
    * @param _withdrawAmount Use `type(uint256).max` to withdraw the maximum available amount.
    */
    function aaveWithdraw(
        bytes32 _idempotencyKey,
        address _token,
        uint256 _withdrawAmount
    ) public onlyRole(SERVICE_ROLE) idempotent(OperationType.AaveWithdraw, _idempotencyKey) whenNotPaused {
        _assertNonZero(_token);
        _assertNonZero(_withdrawAmount);
        _assertOperationLimit(OperationType.AaveWithdraw, _withdrawAmount);

        IAaveTreasuryConnector connector = aaveTreasuryConnector;

        if (_withdrawAmount == type(uint256).max) {
            _withdrawAmount = connector.getATokenBalance(
                connector.isETH(_token)
                    ? connector.getWETHAddress()
                    : _token
            );
        }

        connector.withdraw(_token, _withdrawAmount);

        emit AaveWithdrawn(_idempotencyKey, _token, _withdrawAmount);
    }

    function setAaveTreasuryConnector(
        address _aaveTreasuryConnector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_aaveTreasuryConnector);
        if (_aaveTreasuryConnector.code.length == 0) revert InvalidAaveTreasuryConnector(_aaveTreasuryConnector);

        aaveTreasuryConnector = IAaveTreasuryConnector(_aaveTreasuryConnector);

        emit AaveTreasuryConnectorSet(_aaveTreasuryConnector);
    }

    function aaveRepayAndWithdraw(
        bytes32 _idempotencyKey,
        address _repayToken,
        uint256 _repayAmount,
        address _withdrawToken,
        uint256 _withdrawAmount,
        uint256 _rateMode
    ) external onlyRole(SERVICE_ROLE) whenNotPaused {
        aaveRepay(_idempotencyKey, _repayToken, _repayAmount, _rateMode);
        aaveWithdraw(_idempotencyKey, _withdrawToken, _withdrawAmount);
    }

    function setAaveReferralCode(
        uint16 _aaveReferralCode
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        aaveReferralCode = _aaveReferralCode;

        emit AaveReferralCodeSet(_aaveReferralCode);
    }

    function dineroDeposit(
        bytes32 _idempotencyKey,
        uint256 _amount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.DineroDeposit, _idempotencyKey) whenNotPaused
    returns (uint256 pxETHPostFeeAmount, uint256 feeAmount, uint256 apxETHAmount) {
        _assertNonZero(_amount);
        _assertSufficientFunds(_amount);
        _assertOperationLimit(OperationType.DineroDeposit, _amount);

        // slither-disable-next-line arbitrary-send-eth
        (pxETHPostFeeAmount, feeAmount, apxETHAmount) = dineroTreasuryConnector.deposit{value: _amount}();

        emit DineroDeposited(_idempotencyKey, _amount, pxETHPostFeeAmount, feeAmount, apxETHAmount);

        return (pxETHPostFeeAmount, feeAmount, apxETHAmount);
    }

    function dineroInitiateRedemption(
        bytes32 _idempotencyKey,
        uint256 _apxETHAmount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.DineroInitiateRedemption, _idempotencyKey) whenNotPaused
    returns (uint256 pxETHPostFeeAmount, uint256 feeAmount) {
        _assertNonZero(_apxETHAmount);
        _assertOperationLimit(OperationType.DineroInitiateRedemption, _apxETHAmount);

        APX_ETH.safeIncreaseAllowance(address(dineroTreasuryConnector), _apxETHAmount);

        (pxETHPostFeeAmount, feeAmount) = dineroTreasuryConnector.initiateRedemption(_apxETHAmount);

        emit DineroInitiatedRedemption(_idempotencyKey, _apxETHAmount, pxETHPostFeeAmount, feeAmount);

        return (pxETHPostFeeAmount, feeAmount);
    }

    function dineroInstantRedeemWithApxEth(
        bytes32 _idempotencyKey,
        uint256 _apxETHAmount
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.DineroInstantRedeem, _idempotencyKey) whenNotPaused
    returns (uint256 pxETHPostFeeAmount, uint256 feeAmount) {
        _assertNonZero(_apxETHAmount);
        _assertOperationLimit(OperationType.DineroInstantRedeem, _apxETHAmount);

        APX_ETH.safeIncreaseAllowance(address(dineroTreasuryConnector), _apxETHAmount);

        (pxETHPostFeeAmount, feeAmount) = dineroTreasuryConnector.instantRedeemWithApxEth(_apxETHAmount);

        emit DineroInstantRedeemed(_idempotencyKey, _apxETHAmount, pxETHPostFeeAmount, feeAmount);

        return (pxETHPostFeeAmount, feeAmount);
    }

    function dineroRedeem(
        bytes32 _idempotencyKey,
        uint256[] calldata _upxETHTokenIds
    ) external onlyRole(SERVICE_ROLE) idempotent(OperationType.DineroRedeem, _idempotencyKey) whenNotPaused {
        dineroTreasuryConnector.redeem(_upxETHTokenIds);

        emit DineroRedeemed(_idempotencyKey, _upxETHTokenIds);
    }

    function setDineroTreasuryConnector(
        address _dineroTreasuryConnector
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_dineroTreasuryConnector);
        if (_dineroTreasuryConnector.code.length == 0) revert InvalidDineroTreasuryConnector(_dineroTreasuryConnector);

        dineroTreasuryConnector = IDineroTreasuryConnector(_dineroTreasuryConnector);

        emit DineroTreasuryConnectorSet(_dineroTreasuryConnector);
    }

    function _assertOperationLimit(OperationType _operation, uint256 _amount) internal view {
        if (_amount > operationLimits[_operation]) revert OperationLimitExceeded(_operation, _amount);
    }

    function _assertSufficientFunds(uint256 _amount) internal view {
        if (_amount > address(this).balance) revert InsufficientFunds();
    }

    function _assertNonZero(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    function _assertNonZero(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount(_amount);
    }

}
