// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {IStUSR} from "./interfaces/IStUSR.sol";
import {IDefaultErrors} from "./interfaces/IDefaultErrors.sol";
import {IERC20Rebasing} from "./interfaces/IERC20Rebasing.sol";
import {IWstUSR} from "./interfaces/IWstUSR.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

contract WstUSR is IWstUSR, ERC20PermitUpgradeable, IDefaultErrors {

    using Math for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant ST_USR_SHARES_OFFSET = 1000;

    address public stUSRAddress;
    address public usrAddress;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _stUSRAddress
    ) public initializer {
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);

        _assertNonZero(_stUSRAddress);
        stUSRAddress = _stUSRAddress;

        usrAddress = address(IERC20Rebasing(_stUSRAddress).underlyingToken());
        _assertNonZero(usrAddress);
        IERC20(usrAddress).safeIncreaseAllowance(stUSRAddress, type(uint256).max);
    }

    function asset() external view returns (address usrTokenAddress) {
        return usrAddress;
    }

    function totalAssets() external view returns (uint256 totalManagedUsrAmount) {
        return IERC20Rebasing(stUSRAddress).convertToUnderlyingToken(totalSupply() * ST_USR_SHARES_OFFSET);
    }

    function convertToShares(uint256 _usrAmount) public view returns (uint256 wstUSRAmount) {
        return IERC20Rebasing(stUSRAddress).convertToShares(_usrAmount) / ST_USR_SHARES_OFFSET;
    }

    function convertToAssets(uint256 _wstUSRAmount) public view returns (uint256 usrAmount) {
        return IERC20Rebasing(stUSRAddress).convertToUnderlyingToken(_wstUSRAmount * ST_USR_SHARES_OFFSET);
    }

    function maxDeposit(address) external pure returns (uint256 maxUsrAmount) {
        return type(uint256).max;
    }

    function maxMint(address) external pure returns (uint256 maxWstUSRAmount) {
        return type(uint256).max;
    }

    function maxWithdraw(address _owner) public view returns (uint256 maxUsrAmount) {
        return convertToAssets(balanceOf(_owner));
    }

    function maxRedeem(address owner) public view returns (uint256 maxWstUSRAmount) {
        return balanceOf(owner);
    }

    function previewDeposit(uint256 _usrAmount) public view returns (uint256 wstUSRAmount) {
        return IStUSR(stUSRAddress).previewDeposit(_usrAmount) / ST_USR_SHARES_OFFSET;
    }

    function previewMint(uint256 _wstUSRAmount) public view returns (uint256 usrAmount) {
        IERC20Rebasing stUSR = IERC20Rebasing(stUSRAddress);

        return (_wstUSRAmount * ST_USR_SHARES_OFFSET).mulDiv(
            stUSR.totalSupply() + 1,
            stUSR.totalShares() + ST_USR_SHARES_OFFSET,
            Math.Rounding.Ceil
        );
    }

    function previewWithdraw(uint256 _usrAmount) public view returns (uint256 wstUSRAmount) {
        return IStUSR(stUSRAddress).previewWithdraw(_usrAmount).ceilDiv(ST_USR_SHARES_OFFSET);
    }

    function previewRedeem(uint256 _wstUSRAmount) public view returns (uint256 usrAmount) {
        IERC20Rebasing stUSR = IERC20Rebasing(stUSRAddress);

        return (_wstUSRAmount * ST_USR_SHARES_OFFSET).mulDiv(
            stUSR.totalSupply() + 1,
            stUSR.totalShares() + ST_USR_SHARES_OFFSET,
            Math.Rounding.Floor
        );
    }

    function deposit(uint256 _usrAmount, address _receiver) public returns (uint256 wstUSRAmount) {
        wstUSRAmount = previewDeposit(_usrAmount);
        _deposit(msg.sender, _receiver, _usrAmount, wstUSRAmount);

        return wstUSRAmount;
    }

    function deposit(uint256 _usrAmount) external returns (uint256 wstUSRAmount) {
        return deposit(_usrAmount, msg.sender);
    }

    function depositWithPermit(
        uint256 _usrAmount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 wstUSRAmount) {
        IERC20Permit usrPermit = IERC20Permit(usrAddress);
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try usrPermit.permit(msg.sender, address(this), _usrAmount, _deadline, _v, _r, _s) {} catch {}
        return deposit(_usrAmount, _receiver);
    }

    function mint(uint256 _wstUSRAmount, address _receiver) public returns (uint256 usrAmount) {
        usrAmount = previewMint(_wstUSRAmount);
        _deposit(msg.sender, _receiver, usrAmount, _wstUSRAmount);

        return usrAmount;
    }

    function mint(uint256 _wstUSRAmount) external returns (uint256 usrAmount) {
        return mint(_wstUSRAmount, msg.sender);
    }

    function mintWithPermit(
        uint256 _wstUSRAmount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 usrAmount) {
        IERC20Permit usrPermit = IERC20Permit(usrAddress);
        usrAmount = previewMint(_wstUSRAmount);
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try usrPermit.permit(msg.sender, address(this), usrAmount, _deadline, _v, _r, _s) {} catch {}
        _deposit(msg.sender, _receiver, usrAmount, _wstUSRAmount);

        return usrAmount;
    }

    function withdraw(uint256 _usrAmount, address _receiver, address _owner) public returns (uint256 wstUSRAmount) {
        uint256 maxUsrAmount = maxWithdraw(_owner);
        if (_usrAmount > maxUsrAmount) revert ExceededMaxWithdraw(_owner, _usrAmount, maxUsrAmount);

        wstUSRAmount = previewWithdraw(_usrAmount);
        _withdraw(msg.sender, _receiver, _owner, _usrAmount, wstUSRAmount);

        return wstUSRAmount;
    }

    function withdraw(uint256 _usrAmount) external returns (uint256 wstUSRAmount) {
        return withdraw(_usrAmount, msg.sender, msg.sender);
    }

    function redeem(uint256 _wstUSRAmount, address _receiver, address _owner) public returns (uint256 usrAmount) {
        uint256 maxWstUSRAmount = maxRedeem(_owner);
        if (_wstUSRAmount > maxWstUSRAmount) revert ExceededMaxRedeem(_owner, _wstUSRAmount, maxWstUSRAmount);

        usrAmount = previewRedeem(_wstUSRAmount);
        _withdraw(msg.sender, _receiver, _owner, usrAmount, _wstUSRAmount);

        return usrAmount;
    }

    function redeem(uint256 _wstUSRAmount) external returns (uint256 usrAmount) {
        return redeem(_wstUSRAmount, msg.sender, msg.sender);
    }

    function wrap(uint256 _stUSRAmount, address _receiver) public returns (uint256 wstUSRAmount) {
        _assertNonZero(_stUSRAmount);

        wstUSRAmount = convertToShares(_stUSRAmount);
        IERC20(stUSRAddress).safeTransferFrom(msg.sender, address(this), _stUSRAmount);
        _mint(_receiver, wstUSRAmount);

        emit Wrap(msg.sender, _receiver, _stUSRAmount, wstUSRAmount);

        return wstUSRAmount;
    }

    function wrap(uint256 _stUSRAmount) external returns (uint256 wstUSRAmount) {
        return wrap(_stUSRAmount, msg.sender);
    }

    function wrapWithPermit(
        uint256 _stUSRAmount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 wstUSRAmount) {
        IERC20Permit stUSRPermit = IERC20Permit(stUSRAddress);
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try stUSRPermit.permit(msg.sender, address(this), _stUSRAmount, _deadline, _v, _r, _s) {} catch {}
        return wrap(_stUSRAmount, _receiver);
    }

    function unwrap(uint256 _wstUSRAmount, address _receiver) public returns (uint256 stUSRAmount) {
        _assertNonZero(_wstUSRAmount);

        IERC20Rebasing stUSR = IERC20Rebasing(stUSRAddress);

        uint256 stUSRSharesAmount = _wstUSRAmount * ST_USR_SHARES_OFFSET;
        stUSRAmount = stUSR.convertToUnderlyingToken(stUSRSharesAmount);
        _burn(msg.sender, _wstUSRAmount);
        // slither-disable-next-line unused-return
        stUSR.transferShares(_receiver, stUSRSharesAmount);

        emit Unwrap(msg.sender, _receiver, stUSRAmount, _wstUSRAmount);

        return stUSRAmount;
    }

    function unwrap(uint256 _wstUSRAmount) external returns (uint256 stUSRAmount) {
        return unwrap(_wstUSRAmount, msg.sender);
    }

    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _usrAmount,
        uint256 _wstUSRAmount
    ) internal {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _wstUSRAmount);
        }

        IStUSR stUSR = IStUSR(stUSRAddress);

        stUSR.withdraw(_usrAmount, _receiver);
        _burn(_owner, _wstUSRAmount);

        emit Withdraw(msg.sender, _receiver, _owner, _usrAmount, _wstUSRAmount);
    }

    function _deposit(
        address _caller,
        address _receiver,
        uint256 _usrAmount,
        uint256 _wstUSRAmount
    ) internal {
        IStUSR stUSR = IStUSR(stUSRAddress);
        IERC20 usr = IERC20(usrAddress);

        usr.safeTransferFrom(_caller, address(this), _usrAmount);
        stUSR.deposit(_usrAmount);
        _mint(_receiver, _wstUSRAmount);

        emit Deposit(_caller, _receiver, _usrAmount, _wstUSRAmount);
    }

    function _assertNonZero(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    function _assertNonZero(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount(_amount);
    }
}
