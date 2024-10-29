// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

interface IDineroTreasuryConnector is IDefaultErrors {

    event Deposited(uint256 _amount, uint256 _pxETHPostFeeAmount, uint256 _feeAmount, uint256 _apxETHAmount);
    event InitiatedRedemption(uint256 _apxETHAmount, uint256 _pxETHPostFeeAmount, uint256 _feeAmount);
    event InstantRedeemed(uint256 _apxETHAmount, uint256 _pxETHPostFeeAmount, uint256 _feeAmount);
    event Redeemed(uint256 indexed _upxETHTokenId, uint256 _amount);
    event EmergencyWithdrawnERC20(address indexed _token, address indexed _to, uint256 _amount);
    event EmergencyWithdrawnERC1155(address indexed _token, address indexed _to, uint256 _tokenId, uint256 _amount);

    error EmptyTokensArray();

    function deposit() external payable returns (uint256 pxETHPostFeeAmount, uint256 feeAmount, uint256 apxETHAmount);

    function initiateRedemption(
        uint256 _apxETHAmount
    ) external returns (uint256 pxETHPostFeeAmount, uint256 feeAmount);

    function instantRedeemWithApxEth(
        uint256 _apxETHAmount
    ) external returns (uint256 pxETHPostFeeAmount, uint256 feeAmount);

    function redeem(
        uint256[] calldata _upxETHTokenIds
    ) external;

    function emergencyWithdrawERC20(
        IERC20 _token,
        address _to,
        uint256 _amount
    ) external;

    function emergencyWithdrawERC1155(
        IERC1155 _token,
        address _to,
        uint256 _tokenId
    ) external;

}
