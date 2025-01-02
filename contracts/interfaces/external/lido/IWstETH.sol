// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/**
 * @title ERC-20 value-accruing token wrapper for stETH
 * @dev For more details, see: https://docs.lido.fi/contracts/wsteth
*/
interface IWstETH {

    function balanceOf(address account) external view returns (uint256 balance);

    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256 wstETHAmount);

    // solhint-disable-next-line ordering
    function wrap(uint256 _stETHAmount) external returns (uint256 wstETHAmount);

    function unwrap(uint256 _wstETHAmount) external returns (uint256 stETHAmount);

}
