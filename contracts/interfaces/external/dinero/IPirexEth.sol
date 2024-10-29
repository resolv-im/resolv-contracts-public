// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Main contract for handling interactions with pxETH
 * @dev For more details, see: https://dinero.xyz/docs
 */
interface IPirexEth {

    enum ValidatorStatus {
        None,
        Staking,
        Withdrawable,
        Dissolved,
        Slashed
    }

    enum Fees {
        Deposit,
        Redemption,
        InstantRedemption
    }

    function deposit(
        address _receiver,
        bool _shouldCompound
    ) external payable returns (uint256 postFeeAmount, uint256 feeAmount);

    function initiateRedemption(
        uint256 _assets,
        address _receiver,
        bool _shouldTriggerValidatorExit
    ) external returns (uint256 postFeeAmount, uint256 feeAmount);

    function instantRedeemWithPxEth(
        uint256 _assets,
        address _receiver
    ) external returns (uint256 postFeeAmount, uint256 feeAmount);

    function redeemWithUpxEth(
        uint256 _tokenId,
        uint256 _assets,
        address _receiver
    ) external;

    function fees(Fees fees) external view returns (uint32 feeAmount);

    function batchIdToValidator(uint256 _batchId) external view returns (bytes calldata validator);

    function status(bytes calldata _pubKey) external view returns (ValidatorStatus status);

    function dissolveValidator(bytes calldata _pubKey) external payable;

    function buffer() external view returns (uint256 ethAmount);

}
