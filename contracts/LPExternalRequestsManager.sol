// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ISimpleToken} from "contracts/interfaces/ISimpleToken.sol";
import {ILPExternalRequestsManager} from "./interfaces/ILPExternalRequestsManager.sol";
import {IAddressesWhitelist} from "./interfaces/IAddressesWhitelist.sol";

contract LPExternalRequestsManager is ILPExternalRequestsManager, AccessControlDefaultAdminRules, Pausable {

    using SafeERC20 for IERC20;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");

    address public immutable ISSUE_TOKEN_ADDRESS;
    address public treasuryAddress;

    IAddressesWhitelist public providersWhitelist;
    bool public isWhitelistEnabled;

    mapping(address token => bool isAllowed) public allowedTokens;

    uint256 public mintRequestsCounter;
    mapping(uint256 id => MintRequest request) public mintRequests;

    uint256 public burnRequestsCounter;
    mapping(uint256 id => BurnRequest request) public burnRequests;

    uint256 public burnRequestsPerEpochLimit;
    uint256 public burnEpochCounter;
    mapping(uint256 epochId => Epoch epoch) public burnEpochs;
    mapping(uint256 id => mapping(uint256 epochId => bool exist)) public burnRequestEpochs;

    mapping(bytes32 idempotencyKey => bool exist) private processBurnIdempotencyKeys;
    mapping(bytes32 idempotencyKey => bool exist) private unprocessBurnIdempotencyKeys;
    mapping(bytes32 idempotencyKey => bool exist) private completeBurnIdempotencyKeys;

    modifier onlyAllowedProviders() {
        if (isWhitelistEnabled && !providersWhitelist.isAllowedAccount(msg.sender)) {
            revert UnknownProvider(msg.sender);
        }
        _;
    }

    modifier mintRequestExist(uint256 _id) {
        if (mintRequests[_id].provider == address(0)) {
            revert MintRequestNotExist(_id);
        }
        _;
    }

    modifier burnRequestExist(uint256 _id) {
        if (burnRequests[_id].provider == address(0)) {
            revert BurnRequestNotExist(_id);
        }
        _;
    }

    modifier idempotentProcessBurn(bytes32 _idempotencyKey) {
        if (processBurnIdempotencyKeys[_idempotencyKey]) {
            revert IdempotencyKeyAlreadyExist(_idempotencyKey);
        }
        _;
        processBurnIdempotencyKeys[_idempotencyKey] = true;
    }

    modifier idempotentUnprocessBurn(bytes32 _idempotencyKey) {
        if (unprocessBurnIdempotencyKeys[_idempotencyKey]) {
            revert IdempotencyKeyAlreadyExist(_idempotencyKey);
        }
        _;
        unprocessBurnIdempotencyKeys[_idempotencyKey] = true;
    }

    modifier idempotentCompleteBurn(bytes32 _idempotencyKey) {
        if (completeBurnIdempotencyKeys[_idempotencyKey]) {
            revert IdempotencyKeyAlreadyExist(_idempotencyKey);
        }
        _;
        completeBurnIdempotencyKeys[_idempotencyKey] = true;
    }

    modifier allowedToken(address _tokenAddress) {
        _assertNonZero(_tokenAddress);
        if (!allowedTokens[_tokenAddress]) {
            revert TokenNotAllowed(_tokenAddress);
        }
        _;
    }

    constructor(
        address _issueTokenAddress,
        address _treasuryAddress,
        address _providersWhitelistAddress,
        address[] memory _allowedTokenAddresses,
        uint256 _burnRequestsPerEpochLimit
    ) AccessControlDefaultAdminRules(1 days, msg.sender) {
        ISSUE_TOKEN_ADDRESS = _assertNonZero(_issueTokenAddress);
        treasuryAddress = _assertNonZero(_treasuryAddress);
        providersWhitelist = IAddressesWhitelist(_assertNonZero(_providersWhitelistAddress));

        for (uint256 i = 0; i < _allowedTokenAddresses.length; i++) {
            address allowedTokenAddress = _allowedTokenAddresses[i];
            _assertNonZero(allowedTokenAddress);
            if (allowedTokenAddress.code.length == 0) revert InvalidTokenAddress(allowedTokenAddress);
            if (allowedTokenAddress == _issueTokenAddress) revert InvalidTokenAddress(allowedTokenAddress);
            allowedTokens[allowedTokenAddress] = true;
        }

        burnRequestsPerEpochLimit = _burnRequestsPerEpochLimit;
        isWhitelistEnabled = true;
    }

    function setTreasury(address _treasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_treasuryAddress);
        treasuryAddress = _treasuryAddress;
        emit TreasurySet(_treasuryAddress);
    }

    function setProvidersWhitelist(address _providersWhitelistAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_providersWhitelistAddress);
        if (_providersWhitelistAddress.code.length == 0) revert InvalidProvidersWhitelist(_providersWhitelistAddress);
        providersWhitelist = IAddressesWhitelist(_providersWhitelistAddress);
        emit ProvidersWhitelistSet(_providersWhitelistAddress);
    }

    function setWhitelistEnabled(bool _isEnabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isWhitelistEnabled = _isEnabled;
        emit WhitelistEnabledSet(_isEnabled);
    }

    function setBurnRequestsPerEpochLimit(uint256 _burnRequestsPerEpochLimit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        burnRequestsPerEpochLimit = _burnRequestsPerEpochLimit;
        emit BurnRequestsPerEpochLimitSet(_burnRequestsPerEpochLimit);
    }

    function addAllowedToken(address _allowedTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_allowedTokenAddress);
        if (_allowedTokenAddress.code.length == 0) revert InvalidTokenAddress(_allowedTokenAddress);
        if (_allowedTokenAddress == ISSUE_TOKEN_ADDRESS) revert InvalidTokenAddress(_allowedTokenAddress);

        allowedTokens[_allowedTokenAddress] = true;
        emit AllowedTokenAdded(_allowedTokenAddress);
    }

    function removeAllowedToken(address _allowedTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _assertNonZero(_allowedTokenAddress);
        allowedTokens[_allowedTokenAddress] = false;
        emit AllowedTokenRemoved(_allowedTokenAddress);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }

    function requestMint(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minMintAmount
    ) public onlyAllowedProviders allowedToken(_depositTokenAddress) whenNotPaused {
        _assertAmount(_amount);

        IERC20(_depositTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        MintRequest memory request = _addMintRequest(_depositTokenAddress, _amount, _minMintAmount);

        emit MintRequestCreated(
            request.id,
            request.provider,
            request.token,
            request.amount,
            request.minExpectedAmount
        );
    }

    function requestMintWithPermit(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minMintAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit tokenPermit = IERC20Permit(_depositTokenAddress);
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try tokenPermit.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
        requestMint(_depositTokenAddress, _amount, _minMintAmount);
    }

    function cancelMint(uint256 _id) external mintRequestExist(_id) {
        MintRequest storage request = mintRequests[_id];
        _assertAddress(request.provider, msg.sender);
        _assertState(uint256(MintRequestState.CREATED), uint256(request.state));

        request.state = MintRequestState.CANCELLED;

        IERC20 depositedToken = IERC20(request.token);
        depositedToken.safeTransfer(request.provider, request.amount);

        emit MintRequestCancelled(_id);
    }

    function completeMint(
        bytes32 _idempotencyKey,
        uint256 _id,
        uint256 _mintAmount
    ) external onlyRole(SERVICE_ROLE) mintRequestExist(_id) {
        MintRequest storage request = mintRequests[_id];
        _assertState(uint256(MintRequestState.CREATED), uint256(request.state));
        if (_mintAmount < request.minExpectedAmount) revert InsufficientMintAmount(
            _mintAmount,
            request.minExpectedAmount
        );

        request.state = MintRequestState.COMPLETED;

        IERC20 depositToken = IERC20(request.token);
        depositToken.safeTransfer(treasuryAddress, request.amount);

        ISimpleToken issueToken = ISimpleToken(ISSUE_TOKEN_ADDRESS);
        issueToken.mint(_idempotencyKey, request.provider, _mintAmount);

        emit MintRequestCompleted(_idempotencyKey, _id, _mintAmount);
    }

    function requestBurn(
        address _withdrawalTokenAddress,
        uint256 _amount
    ) public onlyAllowedProviders allowedToken(_withdrawalTokenAddress) whenNotPaused {
        _assertAmount(_amount);

        IERC20 issueToken = IERC20(ISSUE_TOKEN_ADDRESS);
        issueToken.safeTransferFrom(msg.sender, address(this), _amount);

        BurnRequest memory request = _addBurnRequest(_withdrawalTokenAddress, _amount);

        emit BurnRequestCreated(
            request.id,
            request.provider,
            request.token,
            request.requestedToBurnAmount
        );
    }

    function requestBurnWithPermit(
        address _withdrawalTokenAddress,
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit tokenPermit = IERC20Permit(ISSUE_TOKEN_ADDRESS);
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try tokenPermit.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
        requestBurn(_withdrawalTokenAddress, _amount);
    }

    function processBurns(
        bytes32 _idempotencyKey,
        uint256[] calldata _ids
    ) external onlyRole(SERVICE_ROLE) idempotentProcessBurn(_idempotencyKey) {
        uint256 epochId = burnEpochCounter;
        if (epochId != 0 && burnEpochs[epochId - 1].isActive) {
            revert BurnRequestPreviousEpochIsActive(epochId - 1);
        }
        if (_ids.length > burnRequestsPerEpochLimit) {
            revert BurnRequestsLimitExceeded(burnRequestsPerEpochLimit, _ids.length);
        }

        for (uint256 i = 0; i < _ids.length; i++) {
            _processBurn(_idempotencyKey, _ids[i], epochId);
        }

        burnEpochs[epochId] = Epoch({
            isActive: true,
            burnRequestIds: _ids
        });
        unchecked {burnEpochCounter++;}

        emit BurnRequestsEpochProcessing(epochId);
    }

    function unprocessCurrentBurnEpoch(
        bytes32 _idempotencyKey
    ) external onlyRole(SERVICE_ROLE) idempotentUnprocessBurn(_idempotencyKey) {
        uint256 burnEpochCounterValue = burnEpochCounter;
        uint256 currentEpoch = burnEpochCounterValue == 0 ? 0 : burnEpochCounterValue - 1;
        Epoch memory burnEpoch = burnEpochs[currentEpoch];
        if (!burnEpoch.isActive) revert BurnRequestCurrentEpochIsNotActive(currentEpoch);

        uint256[] memory ids = burnEpoch.burnRequestIds;
        for (uint256 i = 0; i < ids.length; i++) {
            _unprocessBurn(_idempotencyKey, ids[i], currentEpoch);
        }

        delete burnEpochs[currentEpoch];
        unchecked {burnEpochCounter--;}

        emit BurnRequestsEpochUnprocessed(currentEpoch);
    }

    function getEpoch(uint256 _epochId) external view returns (Epoch memory epoch) {
        return burnEpochs[_epochId];
    }

    function completeBurns(
        bytes32 _idempotencyKey,
        CompleteBurnItem[] calldata _items,
        address[] calldata _withdrawalTokens
    ) external onlyRole(SERVICE_ROLE) idempotentCompleteBurn(_idempotencyKey) {
        uint256 currentEpoch = burnEpochCounter - 1;
        Epoch memory burnEpoch = burnEpochs[currentEpoch];
        if (!burnEpoch.isActive) revert BurnRequestCurrentEpochIsNotActive(currentEpoch);
        if (burnEpoch.burnRequestIds.length != _items.length) {
            revert InvalidBurnRequestsLength(burnEpoch.burnRequestIds.length, _items.length);
        }

        uint256 totalBurnAmount;
        uint256[] memory totalWithdrawalCollateralAmounts = new uint256[](_withdrawalTokens.length);

        for (uint256 i = 0; i < _items.length; i++) {
            _completeBurn(_idempotencyKey, _items[i], currentEpoch);

            totalBurnAmount += _items[i].burnAmount;

            bool withdrawalTokenFound = false;
            for (uint256 j = 0; j < _withdrawalTokens.length; j++) {
                if (_withdrawalTokens[j] == _items[i].withdrawalToken) {
                    totalWithdrawalCollateralAmounts[j] += _items[i].withdrawalCollateralAmount;
                    withdrawalTokenFound = true;
                    break;
                }
            }
            if (!withdrawalTokenFound) {
                revert WithdrawalTokenNotFound(_items[i].withdrawalToken);
            }
        }

        burnEpochs[currentEpoch].isActive = false;
        ISimpleToken issueToken = ISimpleToken(ISSUE_TOKEN_ADDRESS);
        issueToken.burn(_idempotencyKey, address(this), totalBurnAmount);

        for (uint256 i = 0; i < totalWithdrawalCollateralAmounts.length; i++) {
            if (totalWithdrawalCollateralAmounts[i] > 0) {
                IERC20 withdrawalToken = IERC20(_withdrawalTokens[i]);
                // slither-disable-next-line arbitrary-send-erc20
                withdrawalToken.safeTransferFrom(treasuryAddress, address(this), totalWithdrawalCollateralAmounts[i]);
            }
        }

        emit BurnRequestsEpochCompleted(
            _idempotencyKey,
            currentEpoch,
            totalBurnAmount,
            totalWithdrawalCollateralAmounts
        );
    }


    function cancelBurn(uint256 _id) external burnRequestExist(_id) {
        BurnRequest storage request = burnRequests[_id];
        _assertAddress(request.provider, msg.sender);
        if (BurnRequestState.CREATED != request.state && BurnRequestState.PARTIALLY_COMPLETED != request.state) {
            revert IllegalState(uint256(request.state));
        }

        uint256 remainingAmount = request.requestedToBurnAmount - request.burnedAmount;
        _assertAmount(remainingAmount);

        request.state = BurnRequestState.CANCELLED;
        IERC20 issueToken = IERC20(ISSUE_TOKEN_ADDRESS);
        issueToken.safeTransfer(request.provider, remainingAmount);

        emit BurnRequestCancelled(_id);
    }

    function withdrawAvailableCollateral(uint256 _id) external burnRequestExist(_id) {
        BurnRequest storage request = burnRequests[_id];
        _assertAddress(request.provider, msg.sender);
        _assertAmount(request.withdrawalCollateralAmount);

        uint256 withdrawalCollateralAmount = request.withdrawalCollateralAmount;
        request.withdrawalCollateralAmount = 0;

        IERC20 withdrawalToken = IERC20(request.token);
        withdrawalToken.safeTransfer(msg.sender, withdrawalCollateralAmount);

        emit AvailableCollateralWithdrawn(request.id, withdrawalCollateralAmount);
    }

    function emergencyWithdraw(IERC20 _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = _token.balanceOf(address(this));
        _token.safeTransfer(msg.sender, balance);

        emit EmergencyWithdrawn(address(_token), balance);
    }

    function _addMintRequest(
        address _tokenAddress,
        uint256 _amount,
        uint256 _minExpectedAmount
    ) internal returns (MintRequest memory mintRequest) {
        uint256 id = mintRequestsCounter;
        mintRequest = MintRequest({
            id: id,
            provider: msg.sender,
            state: MintRequestState.CREATED,
            amount: _amount,
            token: _tokenAddress,
            minExpectedAmount: _minExpectedAmount
        });
        mintRequests[id] = mintRequest;

        unchecked {mintRequestsCounter++;}

        return mintRequest;
    }

    function _addBurnRequest(
        address _tokenAddress,
        uint256 _requestedToBurnAmount
    ) internal returns (BurnRequest memory burnRequest) {
        uint256 id = burnRequestsCounter;
        burnRequest = BurnRequest({
            id: id,
            provider: msg.sender,
            state: BurnRequestState.CREATED,
            token: _tokenAddress,
            requestedToBurnAmount: _requestedToBurnAmount,
            burnedAmount: 0,
            withdrawalCollateralAmount: 0
        });
        burnRequests[id] = burnRequest;

        unchecked {burnRequestsCounter++;}

        return burnRequest;
    }

    function _processBurn(
        bytes32 _idempotencyKey,
        uint256 _id,
        uint256 _epochId
    ) internal burnRequestExist(_id) {
        BurnRequest storage request = burnRequests[_id];
        if (BurnRequestState.CREATED != request.state && BurnRequestState.PARTIALLY_COMPLETED != request.state) {
            revert IllegalState(uint256(request.state));
        }

        request.state = BurnRequestState.PROCESSING;
        burnRequestEpochs[request.id][_epochId] = true;

        emit BurnRequestProcessing(_idempotencyKey, _id, _epochId);
    }

    function _unprocessBurn(
        bytes32 _idempotencyKey,
        uint256 _id,
        uint256 _epochId
    ) internal {
        BurnRequest storage request = burnRequests[_id];
        if (BurnRequestState.PROCESSING != request.state) {
            revert IllegalState(uint256(request.state));
        }

        if (request.burnedAmount > 0) {
            request.state = BurnRequestState.PARTIALLY_COMPLETED;
        } else {
            request.state = BurnRequestState.CREATED;
        }
        burnRequestEpochs[request.id][_epochId] = false;

        emit BurnRequestUnprocessed(_idempotencyKey, _id, _epochId);
    }

    function _completeBurn(
        bytes32 _idempotencyKey,
        CompleteBurnItem calldata _item,
        uint256 _epochId
    ) internal burnRequestExist(_item.id) {
        BurnRequest storage request = burnRequests[_item.id];
        _assertState(uint256(BurnRequestState.PROCESSING), uint256(request.state));
        _assertAmount(_item.burnAmount);
        _assertAmount(_item.withdrawalCollateralAmount);
        _assertAddress(request.token, _item.withdrawalToken);
        if (request.burnedAmount + _item.burnAmount > request.requestedToBurnAmount) {
            revert InvalidAmount(_item.burnAmount);
        }

        request.burnedAmount += _item.burnAmount;
        request.withdrawalCollateralAmount += _item.withdrawalCollateralAmount;
        uint256 remainingAmount = request.requestedToBurnAmount - request.burnedAmount;
        if (remainingAmount > 0) {
            request.state = BurnRequestState.PARTIALLY_COMPLETED;
            emit BurnRequestPartiallyCompleted(
                _idempotencyKey,
                _item.id,
                _epochId,
                _item.burnAmount,
                _item.withdrawalCollateralAmount,
                remainingAmount
            );
        } else {
            request.state = BurnRequestState.COMPLETED;
            emit BurnRequestCompleted(
                _idempotencyKey,
                _item.id,
                _epochId,
                _item.burnAmount,
                _item.withdrawalCollateralAmount
            );
        }
    }

    function _assertNonZero(address _address) internal pure returns (address nonZeroAddress) {
        if (_address == address(0)) revert ZeroAddress();
        return _address;
    }

    function _assertState(uint256 _expected, uint256 _current) internal pure {
        if (_expected != _current) revert IllegalState(_current);
    }

    function _assertAddress(address _expected, address _actual) internal pure {
        if (_expected != _actual) revert IllegalAddress(_expected, _actual);
    }

    function _assertAmount(uint256 _amount) internal pure {
        if (_amount == 0) revert InvalidAmount(_amount);
    }

}
