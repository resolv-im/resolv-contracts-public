// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {AccessControlDefaultAdminRulesUpgradeable} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {ERC721HolderUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import {ILido} from "./interfaces/external/lido/ILido.sol";
import {IWstETH} from "./interfaces/external/lido/IWstETH.sol";
import {IWithdrawQueue} from "./interfaces/external/lido/IWithdrawQueue.sol";
import {ILidoTreasuryConnector} from "./interfaces/ILidoTreasuryConnector.sol";

contract LidoTreasuryConnector is ILidoTreasuryConnector, ERC721HolderUpgradeable, AccessControlDefaultAdminRulesUpgradeable {

    using Address for address payable;
    using SafeERC20 for IERC20;

    bytes32 public constant TREASURY_ROLE = keccak256("TREASURY_ROLE");

    address public constant WST_ETH_ADDRESS = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWithdrawQueue public constant WITHDRAW_QUEUE = IWithdrawQueue(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControlDefaultAdminRules_init(1 days, msg.sender);
        __ERC721Holder_init();
    }

    /**
    * @dev Deposits ETH into the Lido pool, converts the received stETH into wstETH, and sends the wstETH to the `msg.sender`.
    * @param _referral The address to receive referral benefits.
    * @return wstETHAmount The amount of wstETH obtained by wrapping stETH.
    * @notice This function will revert if `msg.value` is 0 or exceeds the Lido pool's current stake limit.
    */
    function deposit(address _referral) external payable onlyRole(TREASURY_ROLE) returns (uint256 wstETHAmount) {
        uint256 amount = msg.value;
        _assertAmount(amount);

        ILido lido = LIDO;
        uint256 lidoCurrentStakeLimit = lido.getCurrentStakeLimit();
        if (amount > lidoCurrentStakeLimit) {
            revert StakeLimit(lidoCurrentStakeLimit, amount);
        }

        uint256 stETHShares = lido.submit{value: amount}(_referral);
        uint256 stETHAmount = lido.getPooledEthByShares(stETHShares);

        address wstETHAddress = WST_ETH_ADDRESS;
        IERC20(address(lido)).safeIncreaseAllowance(wstETHAddress, stETHAmount);
        wstETHAmount = IWstETH(wstETHAddress).wrap(stETHAmount);
        IERC20(wstETHAddress).safeTransfer(msg.sender, wstETHAmount);

        emit Deposited(amount, stETHAmount, wstETHAmount);

        return wstETHAmount;
    }

    /**
    * @dev Requests the withdrawal of a batch of wstETH from Lido.
    * @param _amounts An array of wstETH amounts to be withdrawn. Every `amount` must be greater than 100 and less than (1000 * 1e18)
    * @param _totalAmount The total amount of wstETH to increase the allowance for WITHDRAW_QUEUE.
    * @return requestIds An array of the created withdrawal request IDs.
    * @notice This function allows the contract to request the withdrawal of a batch of wstETH from Lido.
    *         `msg.sender` must increase the allowance of wstETH for `_totalAmount` for the contract before calling this method.
    *         The owner of the resulting unstETH NFTs will be `address(this)` (the connector).
    */
    function requestWithdrawals(
        uint256[] calldata _amounts,
        uint256 _totalAmount
    ) external onlyRole(TREASURY_ROLE) returns (uint256[] memory requestIds) {
        _assertAmount(_totalAmount);

        IERC20 wstETH = IERC20(WST_ETH_ADDRESS);
        wstETH.safeTransferFrom(msg.sender, address(this), _totalAmount);

        IWithdrawQueue withdrawQueue = WITHDRAW_QUEUE;
        wstETH.safeIncreaseAllowance(address(withdrawQueue), _totalAmount);
        requestIds = withdrawQueue.requestWithdrawalsWstETH(_amounts, address(this));

        emit WithdrawalsRequested(requestIds, _amounts, _totalAmount);

        return requestIds;
    }

    /**
     * @dev Claim a batch of withdrawal requests
     * @param _requestIds An array of the ASC sorted withdrawal request IDs.
     * @notice Claimed ETH will be sent to the `msg.sender`
     */
    function claimWithdrawals(uint256[] calldata _requestIds) external onlyRole(TREASURY_ROLE) {
        IWithdrawQueue withdrawQueue = WITHDRAW_QUEUE;
        uint256 lastCheckpointIndex = withdrawQueue.getLastCheckpointIndex();
        uint256[] memory hints = withdrawQueue.findCheckpointHints(_requestIds, 1, lastCheckpointIndex);

        withdrawQueue.claimWithdrawalsTo(_requestIds, hints, msg.sender);

        emit WithdrawalsClaimed(_requestIds);
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
     * @dev Allows the DEFAULT_ADMIN to emergency withdraw ERC721 tokens from the contract.
     * @param _token The ERC721 token contract address to withdraw.
     * @param _to The recipient address to receive the token.
     * @param _tokenId The ID of the token to withdraw.
     */
    function emergencyWithdrawERC721(
        IERC721 _token,
        address _to,
        uint256 _tokenId
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(address(_token));
        _assertNonZero(_to);

        _token.safeTransferFrom(address(this), _to, _tokenId);

        emit EmergencyWithdrawnERC721(address(_token), _to, _tokenId);
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
        _assertAmount(_amount);

        _to.sendValue(_amount);

        emit EmergencyWithdrawnETH(_to, _amount);
    }

    function _assertNonZero(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    function _assertAmount(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount(_amount);
    }

}
