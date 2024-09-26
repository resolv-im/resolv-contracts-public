// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IPoolAddressesProvider} from "@aave/core-v3/contracts/interfaces/IPoolAddressesProvider.sol";
import {IPoolDataProvider} from "@aave/core-v3/contracts/interfaces/IPoolDataProvider.sol";
import {IPool} from "@aave/core-v3/contracts/interfaces/IPool.sol";
import {IAaveTreasuryConnector} from "./interfaces/IAaveTreasuryConnector.sol";
import {IWETH} from "./interfaces/external/IWETH.sol";

/**
 * @title AaveV3TreasuryConnector contract
 * @notice A connector contract for interacting with the AaveV3 protocol.
 */
contract AaveV3TreasuryConnector is IAaveTreasuryConnector, AccessControlDefaultAdminRulesUpgradeable {

    using SafeERC20 for IERC20;
    using Address for address payable;

    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    address internal constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    uint256 internal constant STABLE_RATE_MODE = 1;
    uint256 internal constant VARIABLE_RATE_MODE = 2;
    uint256 internal constant MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD_LIMIT = 1e18;

    IPoolAddressesProvider public constant ADDRESSES_PROVIDER = IPoolAddressesProvider(0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e);
    IPoolDataProvider public constant POOL_DATA_PROVIDER = IPoolDataProvider(0x7B4EB56E7CD4b454BA8ff71E4518426369a138a3);
    address public constant WETH_ADDRESS = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public minimumHealthFactorLiquidationThreshold;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initializes the connector with the provided parameters.
     * @param _minimumHealthFactorLiquidationThreshold The minimum health factor threshold for liquidation.
     */
    function initialize(
        uint256 _minimumHealthFactorLiquidationThreshold
    ) public initializer {
        __AccessControlDefaultAdminRules_init(1 days, msg.sender);

        _assertMinimumHealthFactorLiquidationThreshold(_minimumHealthFactorLiquidationThreshold);
        minimumHealthFactorLiquidationThreshold = _minimumHealthFactorLiquidationThreshold;
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    /**
     * @dev Supplies ETH or ERC20 as collateral.
     * @notice This function allows depositing a specific amount of a token into the Aave pool,
     *         using it as collateral for lending.
	 * @param _token The address of the token to deposit. For ETH, use `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`
     * @param _supplyAmount The amount of the token to supply.
     * @param _referralCode Unique code of referral program integration.
     * @dev Enables the user to use the supplied token as collateral if not already enabled.
     *      If `_token` is not ETH (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`), `msg.sender`
     *      must approve this contract to spend at least `_supplyAmount` of `_token` before calling this method.
	 */
    function supply(
        address _token,
        uint256 _supplyAmount,
        uint16 _referralCode
    ) external payable onlyRole(TREASURY_ROLE) {
        _assertNonZero(_token);
        _assertNonZero(_supplyAmount);

        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());

        if (isETH(_token)) {
            if (msg.value != _supplyAmount) revert InvalidAmount(_supplyAmount);

            address wETHAddress = WETH_ADDRESS;
            IWETH wETH = IWETH(wETHAddress);
            wETH.deposit{value: _supplyAmount}();

            IERC20(wETHAddress).safeIncreaseAllowance(address(aavePool), _supplyAmount);
            aavePool.supply(wETHAddress, _supplyAmount, address(this), _referralCode);

            if (!_isUsageAsCollateralEnabled(wETHAddress)) {
                _setUseReserveAsCollateral(wETHAddress, true);
            }
        } else {
            IERC20 token = IERC20(_token);
            token.safeTransferFrom(msg.sender, address(this), _supplyAmount);

            token.safeIncreaseAllowance(address(aavePool), _supplyAmount);
            aavePool.supply(_token, _supplyAmount, address(this), _referralCode);

            if (!_isUsageAsCollateralEnabled(_token)) {
                _setUseReserveAsCollateral(_token, true);
            }
        }

        emit Deposited(_token, _supplyAmount, _referralCode);
    }

    /**
     * @dev Borrow ETH or ERC20 token.
     * @notice Allows borrowing a specific `_borrowAmount` of a token from the Aave pool.
	 * @param _token The address of the token to borrow. For ETH, use `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`
	 * @param _borrowAmount The amount of the ERC20 token to borrow.
	 * @param _rateMode The type of debt: Stable (1) or Variable (2)
	 * @param _referralCode Unique code of referral program integration
	 * @dev Reverts if the health factor falls below the threshold after borrowing.
	 *      If `msg.sender` is a contract and borrows ETH (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`),
     *      it must have implemented the `receive()` function.
	 */
    function borrow(
        address _token,
        uint256 _borrowAmount,
        uint256 _rateMode,
        uint16 _referralCode
    ) external onlyRole(TREASURY_ROLE) {
        _assertNonZero(_token);
        _assertNonZero(_borrowAmount);
        _assertRateMode(_rateMode);

        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());
        if (isETH(_token)) {
            address wETHAddress = WETH_ADDRESS;

            aavePool.borrow(wETHAddress, _borrowAmount, _rateMode, _referralCode, address(this));

            IWETH(wETHAddress).withdraw(_borrowAmount);
            payable(msg.sender).sendValue(_borrowAmount);
        } else {
            aavePool.borrow(_token, _borrowAmount, _rateMode, _referralCode, address(this));

            IERC20(_token).safeTransfer(msg.sender, _borrowAmount);
        }

        _assertHealthFactor();

        emit Borrowed(_token, _borrowAmount, _rateMode, _referralCode);
    }

    /**
     * @dev Repays borrowed ETH or ERC20 token.
	 * @notice Repays a borrowed `_repayAmount` on a specific reserve, burning the equivalent debt tokens owned.
	 * @param _token The address of the token to repay. For ETH, use `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`.
	 * @param _repayAmount The amount of the token to repay. To repay the full amount, use `getCurrentDebt(_token, _rateMode)`
	 * @param _rateMode The type of debt: Stable (1) or Variable (2).
	 * @dev If `_token` is not ETH (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`), `msg.sender`
     *      must approve this contract to spend at least `_repayAmount` of `_token` before calling this method.
	 */
    function repay(
        address _token,
        uint256 _repayAmount,
        uint256 _rateMode
    ) external payable onlyRole(TREASURY_ROLE) {
        _assertNonZero(_token);
        _assertNonZero(_repayAmount);
        _assertRateMode(_rateMode);

        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());
        if (isETH(_token)) {
            if (msg.value != _repayAmount) revert InvalidAmount(_repayAmount);

            address wETHAddress = WETH_ADDRESS;
            IWETH(wETHAddress).deposit{value: _repayAmount}();

            IERC20(wETHAddress).safeIncreaseAllowance(address(aavePool), _repayAmount);
            //slither-disable-next-line unused-return
            aavePool.repay(wETHAddress, _repayAmount, _rateMode, address(this));
        } else {
            IERC20 token = IERC20(_token);
            token.safeTransferFrom(msg.sender, address(this), _repayAmount);

            token.safeIncreaseAllowance(address(aavePool), _repayAmount);
            //slither-disable-next-line unused-return
            aavePool.repay(_token, _repayAmount, _rateMode, address(this));
        }

        emit Repaid(_token, _repayAmount, _rateMode);
    }

    /**
     * @dev Withdraws ETH or ERC20 token from the Aave reserves
	 * @notice Withdraws a `_withdrawAmount` of underlying asset from the reserve, burning the equivalent aTokens owned
	 * @param _token The address of the token to withdraw. For ETH, use `0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`
	 * @param _withdrawAmount The amount of the token to withdraw. To withdraw the full amount, use `getATokenBalance(_token)`
	 * @dev Reverts if the health factor falls below the threshold after withdraw.
	 *      If `msg.sender` is a contract and borrows ETH (`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`),
     *      it must have implemented the `receive()` function.
	 */
    function withdraw(
        address _token,
        uint256 _withdrawAmount
    ) external onlyRole(TREASURY_ROLE) {
        _assertNonZero(_token);
        _assertNonZero(_withdrawAmount);

        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());
        if (isETH(_token)) {
            address wETHAddress = WETH_ADDRESS;

            //slither-disable-next-line unused-return
            aavePool.withdraw(wETHAddress, _withdrawAmount, address(this));

            IWETH(wETHAddress).withdraw(_withdrawAmount);
            payable(msg.sender).sendValue(_withdrawAmount);
        } else {
            //slither-disable-next-line unused-return
            aavePool.withdraw(_token, _withdrawAmount, msg.sender);
        }

        _assertHealthFactor();

        emit Withdrawn(_token, _withdrawAmount);
    }

    /**
    * @dev Sets the efficiency mode
    * @param _eModeCategoryId The category ID of the efficiency mode for treasury asset.
    */
    function setEModeCategory(uint8 _eModeCategoryId) external onlyRole(DEFAULT_ADMIN_ROLE) {
        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());
        aavePool.setUserEMode(_eModeCategoryId);

        _assertHealthFactor();

        emit EModeCategorySet(_eModeCategoryId);
    }

    function setUseReserveAsCollateral(
        address _token,
        bool _useAsCollateral
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _setUseReserveAsCollateral(_token, _useAsCollateral);
    }

    /**
    * @dev Returns the efficiency mode
    * @return eModeCategoryId The category ID of the efficiency mode for treasury asset.
    */
    function getEModeCategory() external view returns (uint256 eModeCategoryId) {
        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());

        return aavePool.getUserEMode(address(this));
    }

    /**
     * @dev Sets a new minimal health factor threshold for liquidation
     * @param _minimumHealthFactorLiquidationThreshold The new minimal health factor threshold.
     */
    function setMinimumHealthFactorLiquidationThreshold(
        uint256 _minimumHealthFactorLiquidationThreshold
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertMinimumHealthFactorLiquidationThreshold(_minimumHealthFactorLiquidationThreshold);
        minimumHealthFactorLiquidationThreshold = _minimumHealthFactorLiquidationThreshold;

        _assertHealthFactor();

        emit MinimalHealthFactorThresholdSet(_minimumHealthFactorLiquidationThreshold);
    }

    /**
     * @dev Returns balance of AToken on current contract
     * @param _token The address of the underlying asset of the AToken
     * @return aTokenBalance The AToken balance
     */
    function getATokenBalance(address _token) external view returns (uint256 aTokenBalance) {
        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());
        address aTokenAddress = aavePool.getReserveData(_token).aTokenAddress;

        return IERC20(aTokenAddress).balanceOf(address(this));
    }

    /**
     * @dev Returns current debt for the rate mode
     * @param _token The address of the underlying asset
     * @return debt The current debt for the rate mode
     */
    function getCurrentDebt(address _token, uint256 _rateMode) external view returns (uint256 debt) {
        _assertRateMode(_rateMode);
        //slither-disable-next-line unused-return
        (, uint256 stableDebt, uint256 variableDebt,,,,,,) = POOL_DATA_PROVIDER.getUserReserveData(_token, address(this));

        return _rateMode == 1 ? stableDebt : variableDebt;
    }

    function isETH(address _token) public pure returns (bool isETHAddress) {
        return _token == ETH;
    }

    function getWETHAddress() external pure returns (address wETHAddress) {
        return WETH_ADDRESS;
    }

    /**
     * @dev Allows the DEFAULT_ADMIN to emergency withdraw ERC20 tokens from the contract.
     * @param _token The ERC20 token contract address to withdraw.
     * @param _to The recipient address to receive the tokens.
     * @param _amount The amount of tokens to withdraw.
     */
    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(address(_token));
        _assertNonZero(_to);
        _assertNonZero(_amount);

        _token.safeTransfer(_to, _amount);

        emit EmergencyWithdrawnERC20(address(_token), _to, _amount);
    }

    /**
     * @dev Allows the DEFAULT_ADMIN to emergency withdraw ETH from the contract.
     * @param _to The recipient address to receive the ETH.
     * @param _amount The amount of ETH to withdraw.
     */
    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_to);
        _assertNonZero(_amount);

        _to.sendValue(_amount);

        emit EmergencyWithdrawnETH(_to, _amount);
    }

    function _setUseReserveAsCollateral(address _token, bool _useAsCollateral) internal {
        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());
        aavePool.setUserUseReserveAsCollateral(_token, _useAsCollateral);
        _assertHealthFactor();

        emit UseReserveAsCollateralSet(_token, _useAsCollateral);
    }

    function _getHealthFactor() internal view returns (uint256 healthFactor) {
        IPool aavePool = IPool(ADDRESSES_PROVIDER.getPool());
        //slither-disable-next-line unused-return
        (,,,,, healthFactor) = aavePool.getUserAccountData(address(this));
        return healthFactor;
    }

    function _isUsageAsCollateralEnabled(address token) internal view returns (bool usageAsCollateralEnabled) {
        //slither-disable-next-line unused-return
        (,,,,,,,, usageAsCollateralEnabled) = POOL_DATA_PROVIDER.getUserReserveData(token, address(this));
        return usageAsCollateralEnabled;
    }

    function _assertHealthFactor() internal view {
        uint256 healthFactor = _getHealthFactor();
        if (healthFactor < minimumHealthFactorLiquidationThreshold) {
            revert HealthFactorBelowMinimumThreshold(healthFactor);
        }
    }

    function _assertRateMode(uint256 _rateMode) internal pure {
        if (_rateMode != STABLE_RATE_MODE && _rateMode != VARIABLE_RATE_MODE) {
            revert InvalidRateMode(_rateMode);
        }
    }

    function _assertMinimumHealthFactorLiquidationThreshold(
        uint256 _minimumHealthFactorLiquidationThreshold
    ) internal pure {
        if (_minimumHealthFactorLiquidationThreshold < MINIMUM_HEALTH_FACTOR_LIQUIDATION_THRESHOLD_LIMIT) {
            revert InvalidMinimumHealthFactorLiquidationThreshold(_minimumHealthFactorLiquidationThreshold);
        }
    }

    function _assertNonZero(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    function _assertNonZero(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount(_amount);
    }
}
