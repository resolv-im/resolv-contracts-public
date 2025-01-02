// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ITreasury} from "./ITreasury.sol";
import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILidoTreasuryExtension is IDefaultErrors {

    event TreasurySet(address _treasury);
    event Wrapped (bytes32 indexed _idempotencyKey, uint256 _stETHAmount, uint256 _wstETHAmount);
    event Unwrapped(bytes32 indexed _idempotencyKey, uint256 _wstETHAmount, uint256 _stETHAmount);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);
    event EmergencyWithdrawnETH(address indexed _to, uint256 _amount);

    function unwrap(bytes32 _idempotencyKey, uint256 _wstETHAmount) external;

    function wrap(bytes32 _idempotencyKey, uint256 _stETHAmount) external;

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external;

    function setTreasury(ITreasury _treasury) external;
}
