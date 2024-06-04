// SPDX-License-Identifier: MIT
/* solhint-disable defi-wonderland/wonder-var-name-mixedcase */
pragma solidity ^0.8.25;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ContextUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC20Rebasing} from "./interfaces/IERC20Rebasing.sol";

/**
 * @title ERC20RebasingUpgradeable
 * @dev This contract is an ERC20-like token that uses a rebasing mechanism.
 * The contract uses the OpenZeppelin ERC20Upgradeable implementation.
 */
abstract contract ERC20RebasingUpgradeable is Initializable, ContextUpgradeable, IERC20Rebasing {
    using Math for uint256;

    /// @custom:storage-location erc7201:openzeppelin.storage.ERC20
    struct ERC20Storage {
        mapping(address account => uint256) _sharesBalances;

        // Allowances are nominated in underlying tokens, not shares.
        mapping(address account => mapping(address spender => uint256)) _allowances;

        uint256 _totalSharesSupply;

        string _name;
        string _symbol;

        IERC20Metadata _underlyingToken;
    }

    // keccak256(abi.encode(uint256(keccak256("openzeppelin.storage.ERC20")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant ERC20_STORAGE_LOCATION = 0x52c63247e1f47db19d5ce0460030c497f067ca4cebf71ba98eeadabe20bace00;

    function _getERC20Storage() private pure returns (ERC20Storage storage $) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := ERC20_STORAGE_LOCATION
        }
    }

    /**
     * @dev Sets the values for {name}, {symbol} and {underlyingToken}.
     *
     * All these values are immutable: they can only be set once during
     * construction.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __ERC20Rebasing_init(
        string memory name_,
        string memory symbol_,
        address underlyingTokenAddress_
    ) internal onlyInitializing {
        __ERC20Rebasing_init_unchained(name_, symbol_, underlyingTokenAddress_);
    }

    // solhint-disable-next-line func-name-mixedcase
    function __ERC20Rebasing_init_unchained(
        string memory name_,
        string memory symbol_,
        address underlyingTokenAddress_
    ) internal onlyInitializing {
        ERC20Storage storage $ = _getERC20Storage();
        $._name = name_;
        $._symbol = symbol_;

        if (underlyingTokenAddress_ == address(0)) revert InvalidUnderlyingTokenAddress();
        $._underlyingToken = IERC20Metadata(underlyingTokenAddress_);
        if ($._underlyingToken.decimals() != 18) revert InvalidUnderlyingTokenDecimals();
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory tokenName) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory tokenSymbol) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._symbol;
    }

    /**
     * @dev Returns the decimals places of the rebasing token.
     */
    function decimals() public pure returns (uint8 tokenDecimals) {
        return 18;
    }

    /**
     * @dev Returns the total supply of rebasing tokens, denominated in underlying tokens.
     */
    function totalSupply() public view returns (uint256 totalUnderlyingTokens) {
        return _totalUnderlyingTokens();
    }

    /**
     * @dev Returns the balance of rebasing tokens for a specific account, denominated in underlying tokens.
     */
    function balanceOf(address _account) public view returns (uint256 balance) {
        return convertToUnderlyingToken(sharesOf(_account));
    }

    /**
     * @dev Returns the underlying token
     */
    function underlyingToken() public view returns (IERC20Metadata token) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._underlyingToken;
    }

    /**
     * @dev Moves a `_underlyingTokenAmount` amount of tokens from the caller's account to `_to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event with `_underlyingTokenAmount` as a value
     * Emits a {TransferShares} event with the corresponding number of shares
     *
     * Requirements:
     *
     * - `_to` cannot be the zero address.
     * - the caller must have a balance of at least `_underlyingTokenAmount`.
     *
     * !IMPORTANT!
     * Due to rounding errors when converting the underlying amount to shares, the number of shares transferred
     * may be less than expected. In some cases, the number of shares can be zero if the exchange rate is highly inflated,
     * leading to no change in balances for both the sender and recipient. This function will successfully execute even if
     * the recipient ends up receiving zero shares.
     *
     * To avoid such issues, it is recommended to use the {transferShares} function instead.
     */
    function transfer(address _to, uint256 _underlyingTokenAmount) public returns (bool isSuccess) {
        address owner = _msgSender();
        uint256 shares = convertToShares(_underlyingTokenAmount);
        // To ensure accuracy in the `Transfer` event, utilize `convertToUnderlyingToken(shares)`
        // instead of using `_underlyingTokenAmount` as is.
        // This prevents discrepancies between the reported 'value' and the actual token amount transferred
        // due to floor rounding during the conversion to shares.
        _transfer(owner, _to, convertToUnderlyingToken(shares), shares);
        return true;
    }

    /**
     * @dev Moves a `_shares` amount from the caller's account to `_to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event with `_underlyingTokenAmount` as a value
     * Emits a {TransferShares} event with the corresponding number of shares
     *
     * Requirements:
     *
     * - `_to` cannot be the zero address.
     * - the caller must have a balance of at least `_shares`.
     */
    function transferShares(address _to, uint256 _shares) public returns (bool isSuccess) {
        address owner = _msgSender();
        uint256 underlyingTokenAmount = convertToUnderlyingToken(_shares);
        _transfer(owner, _to, underlyingTokenAmount, _shares);
        return true;
    }

    /**
     * @dev Returns the remaining number of underlying tokens that `_spender` will be
     * allowed to spend on behalf of `_owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address _owner, address _spender) public view returns (uint256 ownerAllowance) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._allowances[_owner][_spender];
    }

    /**
     * @dev Sets a `_underlyingTokenAmount` amount of tokens as the allowance of `_spender` over the
     * caller's tokens.
     *
     * Emits an {Approval} event.
     */
    function approve(address _spender, uint256 _underlyingTokenAmount) public returns (bool isSuccess) {
        address owner = _msgSender();
        _approve(owner, _spender, _underlyingTokenAmount);
        return true;
    }

    /**
     * @dev Moves a `_underlyingTokenAmount` amount of tokens from `_from` to `_to` using the
     * allowance mechanism. `_underlyingTokenAmount` is then deducted from the caller's
     * allowance.
     *
     * !IMPORTANT!
     * Due to rounding errors when converting the underlying amount to shares, the number of shares transferred
     * may be less than expected. In some cases, the number of shares can be zero if the exchange rate is highly inflated,
     * leading to no change in balances for both the sender and recipient. This function will successfully execute even if
     * the recipient ends up receiving zero shares. The transferred allowance will be fully consumed even if the recipient
     * receives zero shares (and consequently, zero underlying assets).
     *
     * To avoid such issues, it is recommended to use the {transferSharesFrom} function instead.
     */
    function transferFrom(address _from, address _to, uint256 _underlyingTokenAmount) public returns (bool isSuccess) {
        address spender = _msgSender();
        uint256 shares = convertToShares(_underlyingTokenAmount);
        // To ensure accuracy in the `Transfer` event and allowance, utilize `convertToUnderlyingToken(shares)`
        // instead of using `_underlyingTokenAmount` as is.
        // This prevents discrepancies between the reported 'value' and the actual token amount transferred
        // due to floor rounding during the conversion to shares.
        uint256 underlyingTokenAmount = convertToUnderlyingToken(shares);
        _spendAllowance(_from, spender, underlyingTokenAmount);
        _transfer(_from, _to, convertToUnderlyingToken(shares), shares);
        return true;
    }

    /**
     * @dev Moves a `_shares` amount from `_from` to `_to` using the
     * allowance mechanism. `_underlyingTokenAmount` is then deducted from the caller's
     * allowance.
     */
    function transferSharesFrom(address _from, address _to, uint256 _shares) public returns (bool isSuccess) {
        address spender = _msgSender();
        uint256 underlyingTokenAmount = convertToUnderlyingToken(_shares);
        _spendAllowance(_from, spender, underlyingTokenAmount);
        _transfer(_from, _to, underlyingTokenAmount, _shares);
        return true;
    }

    /**
     * @dev Moves a `_underlyingTokenAmount` of tokens from `_from` to `_to`.
     *
     * Emits a {Transfer} event with `_underlyingTokenAmount` as a value
     * Emits a {TransferShares} event with the corresponding number of shares
     */
    function _transfer(address _from, address _to, uint256 _underlyingTokenAmount, uint256 _shares) internal {
        if (_from == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        if (_to == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        _update(_from, _to, _underlyingTokenAmount, _shares);
    }

    /**
     * @dev Transfers a `_underlyingTokenAmount` of tokens from `_from` to `_to`, or alternatively mints (or burns) if `_from`
     * (or `_to`) is the zero address.
     *
     * Emits a {Transfer} event with `_underlyingTokenAmount` as a value
     * Emits a {TransferShares} event with the corresponding number of shares
     */
    function _update(address _from, address _to, uint256 _underlyingTokenAmount, uint256 _shares) internal {
        ERC20Storage storage $ = _getERC20Storage();
        if (_from == address(0)) {
            // Overflow check required: The rest of the code assumes that totalSharesSupply never overflows
            $._totalSharesSupply += _shares;
        } else {
            uint256 fromBalance = $._sharesBalances[_from];
            if (fromBalance < _shares) {
                revert ERC20InsufficientBalance(_from, fromBalance, _shares);
            }
            unchecked {
            // Overflow not possible: shares <= fromBalance <= totalSharesSupply.
                $._sharesBalances[_from] = fromBalance - _shares;
            }
        }

        if (_to == address(0)) {
            unchecked {
            // Overflow not possible: shares <= totalSharesSupply or shares <= fromBalance <= totalSharesSupply.
                $._totalSharesSupply -= _shares;
            }
        } else {
            unchecked {
            // Overflow not possible: sharesBalances + shares is at most totalSharesSupply, which we know fits into a uint256.
                $._sharesBalances[_to] += _shares;
            }
        }

        emit Transfer(_from, _to, _underlyingTokenAmount);
        emit TransferShares(_from, _to, _shares);
    }

    /**
     * @dev Creates a `_shares` amount of tokens and assigns them to `_account`, by transferring it from address(0).
     * Relies on the `_update` mechanism
     *
     * Emits a {Transfer} event with `_from` set to the zero address.
     *
     */
    function _mint(address _account, uint256 _shares) internal {
        if (_account == address(0)) {
            revert ERC20InvalidReceiver(address(0));
        }
        uint256 underlyingTokenAmount = convertToUnderlyingToken(_shares);
        _update(address(0), _account, underlyingTokenAmount, _shares);
    }

    /**
     * @dev Destroys a `_shares` amount of tokens from `_account`, lowering the total shares supply.
     * Relies on the `_update` mechanism.
     *
     * Emits a {Transfer} event with `_to` set to the zero address.
     */
    function _burn(address _account, uint256 _shares) internal {
        if (_account == address(0)) {
            revert ERC20InvalidSender(address(0));
        }
        uint256 underlyingTokenAmount = convertToUnderlyingToken(_shares);
        _update(_account, address(0), underlyingTokenAmount, _shares);
    }

    /**
     * @dev Sets `_underlyingTokenAmount` as the allowance of `_spender` over the `_owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address _owner, address _spender, uint256 _underlyingTokenAmount) internal {
        _approve(_owner, _spender, _underlyingTokenAmount, true);
    }

    /**
     * @dev Variant of {_approve} with an optional flag to enable or disable the {Approval} event.
     *
     * By default (when calling {_approve}) the flag is set to true. On the other hand, approval changes made by
     * `_spendAllowance` during the `transferFrom` operation set the flag to false. This saves gas by not emitting any
     * `Approval` event during `transferFrom` operations.
     *
     * Requirements are the same as {_approve}.
     */
    function _approve(address _owner, address _spender, uint256 _underlyingTokenAmount, bool _emitEvent) internal {
        ERC20Storage storage $ = _getERC20Storage();
        if (_owner == address(0)) {
            revert ERC20InvalidApprover(address(0));
        }
        if (_spender == address(0)) {
            revert ERC20InvalidSpender(address(0));
        }
        $._allowances[_owner][_spender] = _underlyingTokenAmount;
        if (_emitEvent) {
            emit Approval(_owner, _spender, _underlyingTokenAmount);
        }
    }

    /**
     * @dev Updates `_owner` s allowance for `_spender` based on spent `_underlyingTokenAmount`.
     *
     * Does not update the allowance value in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Does not emit an {Approval} event.
     */
    function _spendAllowance(address _owner, address _spender, uint256 _underlyingTokenAmount) internal {
        uint256 currentAllowance = allowance(_owner, _spender);
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < _underlyingTokenAmount) {
                revert ERC20InsufficientAllowance(_spender, currentAllowance, _underlyingTokenAmount);
            }
            unchecked {
                _approve(_owner, _spender, currentAllowance - _underlyingTokenAmount, false);
            }
        }
    }

    /*
    * @dev Returns the total number of shares.
    */
    function totalShares() public view returns (uint256 shares) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._totalSharesSupply;
    }

    /*
    * @dev Returns the number of shares owned by a specific account.
    */
    function sharesOf(address _account) public view returns (uint256 shares) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._sharesBalances[_account];
    }

    function convertToShares(uint256 _underlyingTokenAmount) public view returns (uint256 shares) {
        return _convertToShares(_underlyingTokenAmount, Math.Rounding.Floor);
    }

    function convertToUnderlyingToken(uint256 _shares) public view returns (uint256 underlyingTokenAmount) {
        return _convertToUnderlyingToken(_shares, Math.Rounding.Floor);
    }

    function _convertToShares(
        uint256 _underlyingTokenAmount,
        Math.Rounding _rounding
    ) internal view returns (uint256 shares) {
        return _underlyingTokenAmount.mulDiv(totalShares() + 1000, _totalUnderlyingTokens() + 1, _rounding);
    }

    function _convertToUnderlyingToken(
        uint256 _shares,
        Math.Rounding _rounding
    ) internal view returns (uint256 underlyingTokenAmount) {
        return _shares.mulDiv(_totalUnderlyingTokens() + 1, totalShares() + 1000, _rounding);
    }

    function _totalUnderlyingTokens() internal view returns (uint256 underlyingTokenAmount) {
        ERC20Storage storage $ = _getERC20Storage();
        return $._underlyingToken.balanceOf(address(this));
    }
}
/* solhint-disable defi-wonderland/wonder-var-name-mixedcase */
