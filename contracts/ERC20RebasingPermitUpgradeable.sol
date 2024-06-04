// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {NoncesUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/NoncesUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC20RebasingUpgradeable} from "./ERC20RebasingUpgradeable.sol";

/**
 * @dev Implementation of the ERC20 Permit extension allowing approvals to be made via signatures, as defined in
 * https://eips.ethereum.org/EIPS/eip-2612[EIP-2612].
 *
 * Adds the {permit} method, which can be used to change an account's ERC20 allowance (see {IERC20-allowance}) by
 * presenting a message signed by the account. By not relying on `{IERC20-approve}`, the token holder account doesn't
 * need to send a transaction, and thus is not required to hold Ether at all.
 *
 * The contract uses the OpenZeppelin ERC20PermitUpgradeable implementation.
 */
abstract contract ERC20RebasingPermitUpgradeable is Initializable, ERC20RebasingUpgradeable, IERC20Permit, EIP712Upgradeable, NoncesUpgradeable {
    bytes32 private constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /**
     * @dev Permit deadline has expired.
     */
    error ERC2612ExpiredSignature(uint256 _deadline);

    /**
     * @dev Mismatched signature.
     */
    error ERC2612InvalidSigner(address _signer, address _owner);

    /**
     * @dev Initializes the {EIP712} domain separator using the `name` parameter, and setting `version` to `"1"`.
     *
     * It's a good idea to use the same `name` that is defined as the ERC20 token name.
     */
    // solhint-disable-next-line func-name-mixedcase
    function __ERC20RebasingPermit_init(string memory name) internal onlyInitializing {
        __EIP712_init_unchained(name, "1");
    }

    // solhint-disable-next-line func-name-mixedcase, no-empty-blocks
    function __ERC20RebasingPermit_init_unchained(string memory) internal onlyInitializing {}

    /**
     * @inheritdoc IERC20Permit
     */
    function permit(
        address _owner,
        address _spender,
        uint256 _value,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) public virtual {
        if (block.timestamp > _deadline) {
            revert ERC2612ExpiredSignature(_deadline);
        }

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, _owner, _spender, _value, _useNonce(_owner), _deadline));

        bytes32 hash = _hashTypedDataV4(structHash);

        address signer = ECDSA.recover(hash, _v, _r, _s);
        if (signer != _owner) {
            revert ERC2612InvalidSigner(signer, _owner);
        }

        _approve(_owner, _spender, _value);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    function nonces(
        address _owner
    ) public view virtual override(IERC20Permit, NoncesUpgradeable) returns (uint256 currentNonce) {
        return super.nonces(_owner);
    }

    /**
     * @inheritdoc IERC20Permit
     */
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view virtual returns (bytes32 domainSeparator) {
        return _domainSeparatorV4();
    }
}
