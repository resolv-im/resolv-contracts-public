// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IDefaultErrors} from "./IDefaultErrors.sol";

interface IAddressesWhitelist is IDefaultErrors {

    event AccountAdded(address _account);
    event AccountRemoved(address _account);

    function isAllowedAccount(address _account) external view returns (bool isAllowed);
}
