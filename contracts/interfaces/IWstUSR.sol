// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

interface IWstUSR is IERC4626 {

    event Wrap(address indexed _sender, address indexed _receiver, uint256 _stUSRAmount, uint256 _wstUSRAmount);
    event Unwrap(address indexed _sender, address indexed _receiver, uint256 _stUSRAmount, uint256 _wstUSRAmount);

    error ExceededMaxWithdraw(address _owner, uint256 _usrAmount, uint256 _maxUsrAmount);
    error ExceededMaxRedeem(address _owner, uint256 _wstUSRAmount, uint256 _maxWstUSRAmount);

    function deposit(uint256 _usrAmount) external returns (uint256 wstUSRAmount);

    function depositWithPermit(
        uint256 _usrAmount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 wstUSRAmount);

    function mint(uint256 _wstUSRAmount) external returns (uint256 usrAmount);

    function mintWithPermit(
        uint256 _wstUSRAmount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 usrAmount);

    function withdraw(uint256 _usrAmount) external returns (uint256 wstUSRAmount);

    function redeem(uint256 _wstUSRAmount) external returns (uint256 usrAmount);

    function wrap(uint256 _stUSRAmount, address _receiver) external returns (uint256 wstUSRAmount);

    function wrap(uint256 _stUSRAmount) external returns (uint256 wstUSRAmount);

    function wrapWithPermit(
        uint256 _stUSRAmount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external returns (uint256 wstUSRAmount);

    function unwrap(uint256 _wstUSRAmount, address _receiver) external returns (uint256 stUSRAmount);

    function unwrap(uint256 _wstUSRAmount) external returns (uint256 stUSRAmount);
}
