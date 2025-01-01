// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ITreasury} from "./interfaces/ITreasury.sol";
import {ILidoTreasuryExtension} from "./interfaces/ILidoTreasuryExtension.sol";
import {ILido} from "./interfaces/external/lido/ILido.sol";
import {IWstETH} from "./interfaces/external/lido/IWstETH.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

contract LidoTreasuryExtension is ILidoTreasuryExtension, AccessControlDefaultAdminRules {

    using Address for address payable;
    using SafeERC20 for IERC20;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    address public constant WST_ETH_ADDRESS = address(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);

    ITreasury public treasury;

    constructor(ITreasury _treasury) AccessControlDefaultAdminRules(1 days, msg.sender) {
        setTreasury(_treasury);
    }

    function unwrap(bytes32 _idempotencyKey, uint256 _wstETHAmount) external onlyRole(SERVICE_ROLE) {
        require(_wstETHAmount > 0, InvalidAmount(_wstETHAmount));

        IERC20 wstETH = IERC20(WST_ETH_ADDRESS);
        treasury.increaseAllowance(_idempotencyKey, wstETH, address(this), _wstETHAmount);
        wstETH.safeTransferFrom(address(treasury), address(this), _wstETHAmount);

        uint256 stETHAmount = IWstETH(WST_ETH_ADDRESS).unwrap(_wstETHAmount);
        LIDO.transferShares(address(treasury), LIDO.getSharesByPooledEth(stETHAmount));

        emit Unwrapped(_idempotencyKey, _wstETHAmount, stETHAmount);
    }

    function wrap(bytes32 _idempotencyKey, uint256 _stETHAmount) external onlyRole(SERVICE_ROLE) {
        require(_stETHAmount > 0, InvalidAmount(_stETHAmount));

        IERC20 stETH = IERC20(address(LIDO));
        treasury.increaseAllowance(_idempotencyKey, stETH, address(this), _stETHAmount);
        stETH.safeTransferFrom(address(treasury), address(this), _stETHAmount);

        stETH.safeIncreaseAllowance(WST_ETH_ADDRESS, _stETHAmount);
        uint256 wstETHAmount = IWstETH(WST_ETH_ADDRESS).wrap(_stETHAmount);
        IERC20 wstETH = IERC20(WST_ETH_ADDRESS);
        wstETH.safeTransfer(address(treasury), wstETHAmount);

        emit Wrapped(_idempotencyKey, _stETHAmount, wstETHAmount);
    }

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_token) != address(0), ZeroAddress());
        require(address(_to) != address(0), ZeroAddress());
        require(_amount > 0, InvalidAmount(_amount));

        _token.safeTransfer(_to, _amount);

        emit EmergencyWithdrawnERC20(address(_token), _to, _amount);
    }

    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_to) != address(0), ZeroAddress());
        require(_amount > 0, InvalidAmount(_amount));

        _to.sendValue(_amount);

        emit EmergencyWithdrawnETH(_to, _amount);
    }

    function setTreasury(ITreasury _treasury) public onlyRole(DEFAULT_ADMIN_ROLE) {
        require(address(_treasury) != address(0), ZeroAddress());
        treasury = _treasury;
        emit TreasurySet(address(_treasury));
    }

}
