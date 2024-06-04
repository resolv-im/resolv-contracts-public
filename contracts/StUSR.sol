// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {ERC20RebasingPermitUpgradeable} from "./ERC20RebasingPermitUpgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IStUSR} from "./interfaces/IStUSR.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract StUSR is ERC20RebasingPermitUpgradeable, IStUSR {
    using Math for uint256;
    using SafeERC20 for IERC20Metadata;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _usrAddress
    ) public initializer {
        __ERC20Rebasing_init(_name, _symbol, _usrAddress);
        __ERC20RebasingPermit_init(_name);
    }

    function deposit(uint256 _usrAmount, address _receiver) public {
        uint256 shares = previewDeposit(_usrAmount);
        //slither-disable-next-line incorrect-equality
        if (shares == 0) revert InvalidDepositAmount(_usrAmount);

        IERC20Metadata usr = super.underlyingToken();
        super._mint(_receiver, shares);
        usr.safeTransferFrom(msg.sender, address(this), _usrAmount);
        emit Deposit(msg.sender, _receiver, _usrAmount, shares);
    }

    function deposit(uint256 _usrAmount) external {
        deposit(_usrAmount, msg.sender);
    }

    function depositWithPermit(
        uint256 _usrAmount,
        address _receiver,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public {
        IERC20Metadata usr = super.underlyingToken();
        IERC20Permit usrPermit = IERC20Permit(address(usr));
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try usrPermit.permit(msg.sender, address(this), _usrAmount, _deadline, _v, _r, _s) {} catch {}
        deposit(_usrAmount, _receiver);
    }

    function depositWithPermit(
        uint256 _usrAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        depositWithPermit(_usrAmount, msg.sender, _deadline, _v, _r, _s);
    }

    function withdraw(uint256 _usrAmount) external {
        withdraw(_usrAmount, msg.sender);
    }

    function withdrawAll() external {
        withdraw(super.balanceOf(msg.sender), msg.sender);
    }

    function withdraw(uint256 _usrAmount, address _receiver) public {
        uint256 shares = previewWithdraw(_usrAmount);
        super._burn(msg.sender, shares);

        IERC20Metadata usr = super.underlyingToken();
        usr.safeTransfer(_receiver, _usrAmount);
        emit Withdraw(msg.sender, _receiver, _usrAmount, shares);
    }

    function previewDeposit(uint256 _usrAmount) public view returns (uint256 shares) {
        return _convertToShares(_usrAmount, Math.Rounding.Floor);
    }

    function previewWithdraw(uint256 _usrAmount) public view returns (uint256 shares) {
        return _convertToShares(_usrAmount, Math.Rounding.Ceil);
    }
}
