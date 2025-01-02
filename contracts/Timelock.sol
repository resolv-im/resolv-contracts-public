// SPDX-License-Identifier: MIT
// slither-disable-start pess-timelock-controller
pragma solidity ^0.8.25;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

contract Timelock is TimelockController {

    constructor(
        uint256 _minDelay,
        address[] memory _proposers,
        address[] memory _executors
    ) TimelockController(_minDelay, _proposers, _executors, msg.sender) {}
}
// slither-disable-end pess-timelock-controller
