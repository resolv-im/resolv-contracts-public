// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {IAddressesWhitelist} from "./interfaces/IAddressesWhitelist.sol";

contract AddressesWhitelist is IAddressesWhitelist, Ownable2Step {

    mapping(address account => bool isAllowed) private allowedAccounts;

    constructor() Ownable(msg.sender) {}

    function addAccount(address _account) external onlyOwner {
        if (_account == address(0)) revert ZeroAddress();
        allowedAccounts[_account] = true;
        emit AccountAdded(_account);
    }

    function removeAccount(address _account) external onlyOwner {
        if (_account == address(0)) revert ZeroAddress();
        allowedAccounts[_account] = false;
        emit AccountRemoved(_account);
    }

    function isAllowedAccount(address _account) external view returns (bool isAllowed) {
        return allowedAccounts[_account];
    }
}
