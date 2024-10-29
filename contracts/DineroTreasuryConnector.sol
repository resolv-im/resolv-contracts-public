// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDineroTreasuryConnector} from "./interfaces/IDineroTreasuryConnector.sol";
import {IPirexEth} from  "./interfaces/external/dinero/IPirexEth.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155HolderUpgradeable} from  "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

/**
 * @title DineroTreasuryConnector contract
 * @notice A connector contract for interacting with the Dinero protocol.
 */
contract DineroTreasuryConnector is IDineroTreasuryConnector, ERC1155HolderUpgradeable, AccessControlDefaultAdminRulesUpgradeable {

    using Address for address payable;
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    IERC20 public constant PX_ETH = IERC20(0x04C154b66CB340F3Ae24111CC767e0184Ed00Cc6);
    IERC4626 public constant APX_ETH = IERC4626(0x9Ba021B0a9b958B5E75cE9f6dff97C7eE52cb3E6);
    IERC1155 public constant UPX_ETH = IERC1155(0x5BF2419a33f82F4C1f075B4006d7fC4104C43868);
    IPirexEth public constant PIREX_ETH = IPirexEth(0xD664b74274DfEB538d9baC494F3a4760828B02b0);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControlDefaultAdminRules_init(1 days, msg.sender);
        __ERC1155Holder_init();
    }

    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override(ERC1155HolderUpgradeable, AccessControlDefaultAdminRulesUpgradeable) returns (bool isSupports) {
        return _interfaceId == type(IERC1155Receiver).interfaceId || super.supportsInterface(_interfaceId);
    }

    /**
     * @dev Deposits ETH into Pirex for pxETH and stakes it to receive apxETH.
     * @return pxETHPostFeeAmount The amount of pxETH received after fees.
     * @return feeAmount The fee deducted during deposit.
     * @return apxETHAmount The amount of apxETH received after staking pxETHPostFeeAmoun`.
     * @notice This function will revert if `msg.value` is 0.
     */
    function deposit() external payable onlyRole(TREASURY_ROLE) returns (uint256 pxETHPostFeeAmount, uint256 feeAmount, uint256 apxETHAmount) {
        uint256 amount = msg.value;
        _assertAmount(amount);

        IERC4626 apxETH = APX_ETH;
        (pxETHPostFeeAmount, feeAmount) = PIREX_ETH.deposit{value: amount}(address(this), false);
        PX_ETH.safeIncreaseAllowance(address(apxETH), pxETHPostFeeAmount);
        apxETHAmount = apxETH.deposit(pxETHPostFeeAmount, msg.sender);

        emit Deposited(amount, pxETHPostFeeAmount, feeAmount, apxETHAmount);

        return (pxETHPostFeeAmount, feeAmount, apxETHAmount);
    }

    /**
     * @dev Initiates redemption of apxETH to pxETH.
     * @param _apxETHAmount The amount of apxETH to redeem.
     * @return pxETHPostFeeAmount The amount of pxETH received after fees.
     * @return feeAmount The fee deducted during redemption.
     * @notice For each 32 ETH, 1 upxETH (ERC1155) token will be minted, with 32 ETH in value.
     *      The resulting upxETH tokens will be owned by `address(this)`.
     *      `msg.sender` must increase the allowance of apxETH for `_apxETHAmount` for the contract before calling this method.
     */
    function initiateRedemption(
        uint256 _apxETHAmount
    ) external onlyRole(TREASURY_ROLE) returns (uint256 pxETHPostFeeAmount, uint256 feeAmount) {
        _assertAmount(_apxETHAmount);

        uint256 pxETHAmount = APX_ETH.redeem(_apxETHAmount, address(this), msg.sender);
        (pxETHPostFeeAmount, feeAmount) = PIREX_ETH.initiateRedemption(pxETHAmount, address(this), false);

        emit InitiatedRedemption(_apxETHAmount, pxETHPostFeeAmount, feeAmount);

        return (pxETHPostFeeAmount, feeAmount);
    }

    /**
     * @dev Instant redeem of apxETH to ETH.
     * @param _apxETHAmount The amount of apxETH to redeem.
     * @return pxETHPostFeeAmount The amount of pxETH received after fees.
     * @return feeAmount The fee deducted during redemption.
     * @notice `msg.sender` must increase the allowance of apxETH for `_apxETHAmount` for the contract before calling this method.
     */
    function instantRedeemWithApxEth(
        uint256 _apxETHAmount
    ) external onlyRole(TREASURY_ROLE) returns (uint256 pxETHPostFeeAmount, uint256 feeAmount) {
        _assertAmount(_apxETHAmount);

        uint256 pxETHAmount = APX_ETH.redeem(_apxETHAmount, address(this), msg.sender);
        (pxETHPostFeeAmount, feeAmount) = PIREX_ETH.instantRedeemWithPxEth(pxETHAmount, msg.sender);

        emit InstantRedeemed(_apxETHAmount, pxETHPostFeeAmount, feeAmount);

        return (pxETHPostFeeAmount, feeAmount);
    }

    /**
     * @dev Redeems a batch of upxETH tokens for ETH.
     * @param _upxETHTokenIds An array of upxETH token IDs to redeem.
     * @notice The redeemed ETH will be sent to `msg.sender`.
     */
    function redeem(
        uint256[] calldata _upxETHTokenIds
    ) external onlyRole(TREASURY_ROLE) {
        uint256 upxETHTokenIdsLength = _upxETHTokenIds.length;
        if (_upxETHTokenIds.length == 0) revert EmptyTokensArray();

        for (uint256 i = 0; i < upxETHTokenIdsLength; i++) {
            uint256 amount = UPX_ETH.balanceOf(address(this), _upxETHTokenIds[i]);
            _assertAmount(amount);
            uint256 tokenId = _upxETHTokenIds[i];
            PIREX_ETH.redeemWithUpxEth(tokenId, amount, msg.sender);

            emit Redeemed(tokenId, amount);
        }
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
        _assertAmount(_amount);

        _token.safeTransfer(_to, _amount);

        emit EmergencyWithdrawnERC20(address(_token), _to, _amount);
    }

    /**
     * @dev Allows the DEFAULT_ADMIN to emergency withdraw ERC1155 tokens from the contract using the whole balance of a token.
     * @param _token The ERC1155 token contract address to withdraw.
     * @param _to The recipient address to receive the tokens.
     * @param _tokenId The token ID to withdraw.
     */
    function emergencyWithdrawERC1155(
        IERC1155 _token,
        address _to,
        uint256 _tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(address(_token));
        _assertNonZero(_to);

        uint256 _balance = _token.balanceOf(address(this), _tokenId);
        _token.safeTransferFrom(address(this), _to, _tokenId, _balance, "");

        emit EmergencyWithdrawnERC1155(address(_token), _to, _tokenId, _balance);
    }

    function _assertNonZero(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    function _assertAmount(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount(_amount);
    }
}
