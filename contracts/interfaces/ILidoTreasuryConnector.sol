// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface ILidoTreasuryConnector is IDefaultErrors {

    event Deposited(uint256 _amount, uint256 _stETHAmount, uint256 _wstETHBalance);
    event WithdrawalsRequested(uint256[] _requestIds, uint256[] _amounts, uint256 _totalAmount);
    event WithdrawalsClaimed(uint256[] _requestIds);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);
    event EmergencyWithdrawnERC721(address indexed _token, address indexed _to, uint256 _tokenId);
    event EmergencyWithdrawnETH(address indexed _to, uint256 _amount);

    error StakeLimit(uint256 _lidoCurrentStakeLimit, uint256 _amount);

    function deposit(address _referral) external payable returns (uint256 wstETHAmount);

    function requestWithdrawals(
        uint256[] calldata _amounts,
        uint256 _totalAmount
    ) external returns (uint256[] memory requestIds);

    function claimWithdrawals(uint256[] calldata _requestIds) external;

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function emergencyWithdrawERC721(
        IERC721 _token,
        address _to,
        uint256 _tokenId
    ) external;

    function emergencyWithdrawETH(
        address payable _to,
        uint256 _amount
    ) external;
}
