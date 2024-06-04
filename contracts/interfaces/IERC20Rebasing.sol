// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

interface IERC20Rebasing is IERC20, IERC20Metadata, IERC20Errors {
    event TransferShares(address indexed _from, address indexed _to, uint256 _shares);

    error InvalidUnderlyingTokenDecimals();
    error InvalidUnderlyingTokenAddress();

    function underlyingToken() external view returns (IERC20Metadata token);

    function transferShares(address _to, uint256 _shares) external returns (bool isSuccess);

    function transferSharesFrom(address _from, address _to, uint256 _shares) external returns (bool isSuccess);

    function totalShares() external view returns (uint256 shares);

    function sharesOf(address _account) external view returns (uint256 shares);

    function convertToShares(uint256 _underlyingTokenAmount) external view returns (uint256 shares);

    function convertToUnderlyingToken(uint256 _shares) external view returns (uint256 underlyingTokenAmount);
}
