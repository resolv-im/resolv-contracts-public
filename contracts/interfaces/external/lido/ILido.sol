// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title Liquid staking pool and a related ERC-20 rebasing token (stETH)
 * @dev For more details, see: https://docs.lido.fi/contracts/lido
*/
interface ILido {

    function getCurrentStakeLimit() external view returns (uint256 stakeLimit);

    function getSharesByPooledEth(uint256 _ethAmount) external view returns (uint256 stETHShares);

    function getPooledEthByShares(uint256 _stETHShares) external view returns (uint256 _ethAmount);

    function sharesOf(address _account) external view returns (uint256 stETHAmount);

    // solhint-disable-next-line ordering
    function submit(address _referral) external payable returns (uint256 stETHAmount);

    function transferShares(address _recipient, uint256 _sharesAmount) external returns (uint256 sharesAmount);

}
