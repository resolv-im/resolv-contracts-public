// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAaveTreasuryConnector is IDefaultErrors {

    event Received(address indexed _from, uint256 _amount);
    event Deposited(address _token, uint256 _amount, uint16 _referralCode);
    event Borrowed(address _token, uint256 _amount, uint256 _rateMode, uint16 _referralCode);
    event Repaid(address _token, uint256 _amount, uint256 _rateMode);
    event Withdrawn(address _token, uint256 _amount);
    event MinimalHealthFactorThresholdSet(uint256 _minimalHealthFactorThreshold);
    event UseReserveAsCollateralSet(address _token, bool _useAsCollateral);
    event EModeCategorySet(uint256 _eModeCategoryId);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);
    event EmergencyWithdrawnETH(address indexed _to, uint256 _amount);

    error InvalidMinimumHealthFactorLiquidationThreshold(uint256 _threshold);
    error HealthFactorBelowMinimumThreshold(uint256 _healthFactor);
    error InvalidRateMode(uint256 _rateMode);

    function supply(
        address _token,
        uint256 _supplyAmount,
        uint16 _referralCode
    ) external payable;

    function borrow(
        address _token,
        uint256 _borrowAmount,
        uint256 _rateMode,
        uint16 _referralCode
    ) external;

    function repay(
        address _token,
        uint256 _repayAmount,
        uint256 _rateMode
    ) external payable;

    function withdraw(
        address _token,
        uint256 _withdrawAmount
    ) external;

    function setEModeCategory(uint8 _eModeCategoryId) external;

    function setUseReserveAsCollateral(address _token, bool _useAsCollateral) external;

    function getEModeCategory() external view returns (uint256 eModeCategoryId);

    function setMinimumHealthFactorLiquidationThreshold(
        uint256 _minimumHealthFactorLiquidationThreshold
    ) external;

    function getATokenBalance(address _token) external view returns (uint256 aTokenBalance);

    function getCurrentDebt(
        address _token,
        uint256 _rateMode
    ) external view returns (uint256 debt);

    function isETH(address _token) external pure returns (bool isETHAddress);

    function getWETHAddress() external pure returns (address wETHAddress);

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external;
}
