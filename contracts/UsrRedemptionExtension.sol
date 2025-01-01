// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISimpleToken} from "./interfaces/ISimpleToken.sol";
import {ITreasury} from "./interfaces/ITreasury.sol";
import {IUsrRedemptionExtension} from "./interfaces/IUsrRedemptionExtension.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IChainlinkOracle} from "./interfaces/oracles/IChainlinkOracle.sol";
import {IUsrPriceStorage} from "./interfaces/IUsrPriceStorage.sol";

contract UsrRedemptionExtension is IUsrRedemptionExtension, AccessControlDefaultAdminRules, Pausable {

    using SafeERC20 for IERC20;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");

    uint256 internal constant AAVE_VARIABLE_RATE_MODE = 2;

    string internal constant IDEMPOTENCY_KEY_PREFIX = "UsrRedemptionExtension";
    uint256 internal immutable USR_DECIMALS;
    address public immutable USR_TOKEN_ADDRESS;

    ITreasury public treasury;
    IChainlinkOracle public chainlinkOracle;
    IUsrPriceStorage public usrPriceStorage;
    uint256 public usrPriceStorageHeartbeatInterval;
    uint256 public redemptionLimit;
    uint256 public currentRedemptionUsage;
    uint256 public lastResetTime;
    uint256 public redeemCounter;
    mapping(address token => bool isAllowed) public allowedWithdrawalTokens;

    modifier allowedWithdrawalToken(address _tokenAddress) {
        _assertNonZero(_tokenAddress);
        if (!allowedWithdrawalTokens[_tokenAddress]) {
            revert TokenNotAllowed(_tokenAddress);
        }
        _;
    }

    constructor(
        address _usrTokenAddress,
        address[] memory _allowedWithdrawalTokenAddresses,
        ITreasury _treasury,
        IChainlinkOracle _chainlinkOracle,
        IUsrPriceStorage _usrPriceStorage,
        uint256 _usrPriceStorageHeartbeatInterval,
        uint256 _redemptionLimit,
        uint256 _lastResetTime
    ) AccessControlDefaultAdminRules(1 days, msg.sender) {
        _assertNonZero(_usrTokenAddress);
        USR_TOKEN_ADDRESS = _usrTokenAddress;
        USR_DECIMALS = IERC20Metadata(_usrTokenAddress).decimals();
        setTreasury(_treasury);
        setChainlinkOracle(_chainlinkOracle);
        setUsrPriceStorage(_usrPriceStorage);
        setUsrPriceStorageHeartbeatInterval(_usrPriceStorageHeartbeatInterval);
        setRedemptionLimit(_redemptionLimit);

        for (uint256 i = 0; i < _allowedWithdrawalTokenAddresses.length; i++) {
            addAllowedWithdrawalToken(_allowedWithdrawalTokenAddresses[i]);
        }

        currentRedemptionUsage = 0;
        if (_lastResetTime < block.timestamp ||
            _lastResetTime > block.timestamp + 1 days) revert InvalidLastResetTime(_lastResetTime);
        lastResetTime = _lastResetTime;
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }

    function redeem(uint256 _amount, address _withdrawalTokenAddress) external {
        redeem(_amount, msg.sender, _withdrawalTokenAddress);
    }

    function removeAllowedWithdrawalToken(
        address _allowedWithdrawalTokenAddress
    ) external onlyRole(DEFAULT_ADMIN_ROLE) allowedWithdrawalToken(_allowedWithdrawalTokenAddress) {
        allowedWithdrawalTokens[_allowedWithdrawalTokenAddress] = false;
        emit AllowedWithdrawalTokenRemoved(_allowedWithdrawalTokenAddress);
    }

    function addAllowedWithdrawalToken(address _allowedWithdrawalTokenAddress) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_allowedWithdrawalTokenAddress);
        if (allowedWithdrawalTokens[_allowedWithdrawalTokenAddress]) revert TokenAlreadyAllowed(_allowedWithdrawalTokenAddress);
        if (_allowedWithdrawalTokenAddress.code.length == 0) revert InvalidTokenAddress(_allowedWithdrawalTokenAddress);
        allowedWithdrawalTokens[_allowedWithdrawalTokenAddress] = true;
        emit AllowedWithdrawalTokenAdded(_allowedWithdrawalTokenAddress);
    }

    function setTreasury(ITreasury _treasury) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(address(_treasury));
        treasury = _treasury;
        emit TreasurySet(address(_treasury));
    }

    function setChainlinkOracle(IChainlinkOracle _chainlinkOracle) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(address(_chainlinkOracle));
        chainlinkOracle = _chainlinkOracle;
        emit ChainlinkOracleSet(address(_chainlinkOracle));
    }

    function setUsrPriceStorage(IUsrPriceStorage _usrPriceStorage) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(address(_usrPriceStorage));
        usrPriceStorage = _usrPriceStorage;
        emit UsrPriceStorageSet(address(_usrPriceStorage));
    }

    function setUsrPriceStorageHeartbeatInterval(uint256 _usrPriceStorageHeartbeatInterval) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_usrPriceStorageHeartbeatInterval);
        usrPriceStorageHeartbeatInterval = _usrPriceStorageHeartbeatInterval;
        emit UsrPriceStorageHeartbeatIntervalSet(_usrPriceStorageHeartbeatInterval);
    }

    function setRedemptionLimit(uint256 _redemptionLimit) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_redemptionLimit);
        redemptionLimit = _redemptionLimit;
        emit RedemptionLimitSet(_redemptionLimit);
    }

    // slither-disable-start pess-multiple-storage-read
    function redeem(
        uint256 _amount,
        address _receiver,
        address _withdrawalTokenAddress
    ) public whenNotPaused allowedWithdrawalToken(_withdrawalTokenAddress) onlyRole(SERVICE_ROLE) returns (uint256 withdrawalTokenAmount) {
        _assertNonZero(_amount);
        _assertNonZero(_receiver);

        uint256 currentTime = block.timestamp;
        if (currentTime >= lastResetTime + 1 days) {
            // slither-disable-start divide-before-multiply
            uint256 periodsPassed = (currentTime - lastResetTime) / 1 days;
            lastResetTime += periodsPassed * 1 days;
            // slither-disable-end divide-before-multiply

            currentRedemptionUsage = 0;

            emit RedemptionLimitReset(lastResetTime);
        }

        currentRedemptionUsage += _amount;
        if (currentRedemptionUsage > redemptionLimit) {
            revert RedemptionLimitExceeded(_amount, redemptionLimit);
        }

        bytes32 idempotencyKey = generateIdempotencyKey();
        ISimpleToken(USR_TOKEN_ADDRESS).burn(
            idempotencyKey,
            msg.sender,
            _amount
        );

        uint8 withdrawalTokenDecimals = IERC20Metadata(_withdrawalTokenAddress).decimals();
        // slither-disable-next-line unused-return
        (,int256 redeemPrice,,,) = getRedeemPrice(_withdrawalTokenAddress);
        if (withdrawalTokenDecimals > USR_DECIMALS) {
            // slither-disable-next-line pess-dubious-typecast
            // slither-disable-next-line divide-before-multiply
            withdrawalTokenAmount = (_amount * (10 ** USR_DECIMALS) / uint256(redeemPrice))
                * 10 ** (withdrawalTokenDecimals - USR_DECIMALS);
        } else {
            // slither-disable-next-line pess-dubious-typecast
            withdrawalTokenAmount = (_amount * (10 ** USR_DECIMALS) / uint256(redeemPrice))
                / 10 ** (USR_DECIMALS - withdrawalTokenDecimals);
        }

        IERC20 withdrawalToken = IERC20(_withdrawalTokenAddress);
        uint256 treasuryWithdrawalTokenBalance = withdrawalToken.balanceOf(address(treasury));

        if (treasuryWithdrawalTokenBalance < withdrawalTokenAmount) {
            treasury.aaveBorrow(
                idempotencyKey,
                _withdrawalTokenAddress,
                withdrawalTokenAmount - treasuryWithdrawalTokenBalance,
                AAVE_VARIABLE_RATE_MODE
            );
        }
        treasury.increaseAllowance(
            idempotencyKey,
            withdrawalToken,
            address(this),
            withdrawalTokenAmount
        );

        // slither-disable-next-line arbitrary-send-erc20
        withdrawalToken.safeTransferFrom(address(treasury), _receiver, withdrawalTokenAmount);

        emit Redeemed(
            msg.sender,
            _receiver,
            _amount,
            _withdrawalTokenAddress,
            withdrawalTokenAmount
        );

        return withdrawalTokenAmount;
    }

    function getRedeemPrice(address _withdrawalTokenAddress) public view returns (
        uint80 roundId,
        int256 price,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        IChainlinkOracle oracle = chainlinkOracle;
        (
            roundId,
            price,
            startedAt,
            updatedAt,
            answeredInRound
        ) = oracle.getLatestRoundData(_withdrawalTokenAddress);
        uint8 priceDecimals = oracle.priceDecimals(_withdrawalTokenAddress);

        if (priceDecimals > USR_DECIMALS) {
            price = SafeCast.toInt256(SafeCast.toUint256(price) / 10 ** (priceDecimals - USR_DECIMALS));
        } else if (priceDecimals < USR_DECIMALS) {
            price = SafeCast.toInt256(SafeCast.toUint256(price) * 10 ** (USR_DECIMALS - priceDecimals));
        }

        price = SafeCast.toInt256(SafeCast.toUint256(price) * usrPriceStorage.PRICE_SCALING_FACTOR() / getUSRPrice());

        return (roundId, price, startedAt, updatedAt, answeredInRound);
    }
    // slither-disable-end pess-multiple-storage-read

    function generateIdempotencyKey() internal returns (bytes32 idempotencyKey) {
        idempotencyKey = keccak256(abi.encodePacked(IDEMPOTENCY_KEY_PREFIX, redeemCounter));
        unchecked {redeemCounter++;}

        return idempotencyKey;
    }

    function getUSRPrice() internal view returns (uint256 usrPrice) {
        // slither-disable-next-line unused-return
        (uint256 price,,,uint256 timestamp) = usrPriceStorage.lastPrice();
        if (timestamp + usrPriceStorageHeartbeatInterval < block.timestamp) {
            revert UsrPriceHeartbeatIntervalCheckFailed();
        }
        if (price < usrPriceStorage.PRICE_SCALING_FACTOR()) {
            revert InvalidUsrPrice(price);
        }

        return usrPrice = price;
    }

    function _assertNonZero(address _address) internal pure {
        if (_address == address(0)) revert ZeroAddress();
    }

    function _assertNonZero(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount(_amount);
    }
}
