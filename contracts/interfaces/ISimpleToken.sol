// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

interface ISimpleToken {

    error IdempotencyKeyAlreadyExist(bytes32 idempotencyKey);

    function mint(address _account, uint256 _amount) external;

    function mint(bytes32 _idempotencyKey, address _account, uint256 _amount) external;

    function burn(address _account, uint256 _amount) external;

    function burn(bytes32 _idempotencyKey, address _account, uint256 _amount) external;
}
