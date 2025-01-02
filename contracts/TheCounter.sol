// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {AccessControlDefaultAdminRules} from "@openzeppelin/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ITheCounter} from "./interfaces/ITheCounter.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISimpleToken} from "./interfaces/ISimpleToken.sol";

contract TheCounter is ITheCounter, AccessControlDefaultAdminRules, Pausable {

    using SafeERC20 for IERC20;

    bytes32 public constant SERVICE_ROLE = keccak256("SERVICE_ROLE");
    uint256 public constant FEE_DENOMINATOR = 10 ** 6;
    uint256 public constant MAX_FEE = 10 ** 5;

    address public immutable SWAP_TOKEN_ADDRESS;

    uint256 public fee;
    uint256 public collectedFee;

    uint256 public swapRequestsCounter;
    mapping(uint256 id => Request request) public swapRequests;

    mapping(address token => uint256 minSwapAmount) public minSwapAmounts;
    mapping(address token => bool isAllowed) public allowedTokens;

    address public treasury;

    modifier swapRequestExist(uint256 _id) {
       require(swapRequests[_id].provider != address(0), SwapRequestNotExist(_id));
        _;
    }

    modifier allowedToken(address _tokenAddress) {
        require(_tokenAddress != address(0), ZeroAddress());
        require(allowedTokens[_tokenAddress], TokenNotAllowed(_tokenAddress));
        _;
    }

    constructor(
        address _swapTokenAddress,
        address[] memory _allowedTokens,
        uint256[] memory _minSwapAmounts,
        uint256 _fee,
        address _treasury
    ) AccessControlDefaultAdminRules(1 days, msg.sender) {
        require(_swapTokenAddress != address(0), ZeroAddress());
        SWAP_TOKEN_ADDRESS = _swapTokenAddress;
        require(_allowedTokens.length == _minSwapAmounts.length, IllegalMinSwapParameters(_allowedTokens, _minSwapAmounts));

        for (uint256 i = 0; i < _allowedTokens.length; i ++) {
            address _tokenAddress = _allowedTokens[i];
            require(_tokenAddress != address(0), ZeroAddress());
            minSwapAmounts[_tokenAddress] = _minSwapAmounts[i];
            allowedTokens[_tokenAddress] = true;
        }

        require(_fee > 0, ZeroFee());
        fee = _fee;

        require(_treasury != address(0), ZeroAddress());
        treasury = _treasury;
    }

    function setTreasury(address _treasuryAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_treasuryAddress != address(0), ZeroAddress());
        treasury = _treasuryAddress;
        emit TreasurySet(_treasuryAddress);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        Pausable._unpause();
    }

    function emergencyWithdraw(IERC20 _token) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 balance = _token.balanceOf(address(this));
        _token.safeTransfer(msg.sender, balance);

        emit EmergencyWithdrawn(address(_token), balance);
    }

    function requestSwapWithPermit(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minExpectedAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external {
        IERC20Permit tokenPermit = IERC20Permit(_depositTokenAddress);
        // the use of `try/catch` allows the permit to fail and makes the code tolerant to frontrunning.
        // solhint-disable-next-line no-empty-blocks
        try tokenPermit.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
        requestSwap(_depositTokenAddress, _amount, _minExpectedAmount);
    }

    function cancelSwap(uint256 _id) external swapRequestExist(_id) {
        Request storage request = swapRequests[_id];
        require(request.provider == msg.sender, IllegalAddress(request.provider, msg.sender));
        require(State.CREATED == request.state, IllegalState(State.CREATED, request.state));

        request.state = State.CANCELLED;

        IERC20 depositedToken = IERC20(request.token);
        depositedToken.safeTransfer(request.provider, request.amount);

        emit SwapRequestCancelled(_id);
    }

    function completeSwap(
        bytes32 _idempotencyKey,
        uint256 _id,
        uint256 _targetAmount
    ) external onlyRole(SERVICE_ROLE) swapRequestExist(_id) {
        Request storage request = swapRequests[_id];
        require(State.CREATED == request.state, IllegalState(State.CREATED, request.state));
        uint256 takenFee = (_targetAmount * fee) / FEE_DENOMINATOR;
        uint256 transferableAmount = _targetAmount - takenFee;
        uint256 minExpectedAmount = request.minExpectedAmount;
        require(transferableAmount >= minExpectedAmount, InsufficientAmount(transferableAmount, minExpectedAmount));

        request.state = State.COMPLETED;

        IERC20 requestToken = IERC20(request.token);
        requestToken.safeTransfer(treasury, request.amount);

        ISimpleToken simpleToken = ISimpleToken(SWAP_TOKEN_ADDRESS);
        simpleToken.mint(_idempotencyKey, address(this), _targetAmount);
        collectedFee += takenFee;
        IERC20 token = IERC20(SWAP_TOKEN_ADDRESS);
        token.safeTransfer(request.provider, transferableAmount);

        emit SwapRequestCompleted(_idempotencyKey, _id, transferableAmount, takenFee);
    }

    function setFee(uint256 _feePart) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_feePart <= MAX_FEE, FeeMoreThanMaxFee(_feePart, MAX_FEE));

        fee = _feePart;

        emit FeeSet(_feePart);
    }

    function setMinSwapAmount(address requestedTokenAddress, uint256 newAmount) allowedToken(requestedTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(requestedTokenAddress != address(0), ZeroAddress());
        require(requestedTokenAddress.code.length > 0, AddressIsNotContract(requestedTokenAddress));
        minSwapAmounts[requestedTokenAddress] = newAmount;
        emit MinimumSwapAmountSet(requestedTokenAddress, newAmount);
    }

    function transferFee() external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 feeToTransfer = collectedFee;
        collectedFee = 0;
        IERC20 token = IERC20(SWAP_TOKEN_ADDRESS);
        token.safeTransfer(msg.sender, feeToTransfer);

        emit FeeTransferred(feeToTransfer);
    }

    function addAllowedToken(address _allowedTokenAddress, uint256 _minSwapAmount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_allowedTokenAddress != address(0), ZeroAddress());
        require(_allowedTokenAddress.code.length != 0, InvalidTokenAddress(_allowedTokenAddress));
        allowedTokens[_allowedTokenAddress] = true;
        minSwapAmounts[_allowedTokenAddress] = _minSwapAmount;
        emit AllowedTokenAdded(_allowedTokenAddress);
    }

    function removeAllowedToken(address _allowedTokenAddress) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_allowedTokenAddress != address(0), ZeroAddress());
        require(_allowedTokenAddress.code.length != 0, InvalidTokenAddress(_allowedTokenAddress));
        allowedTokens[_allowedTokenAddress] = false;
        emit AllowedTokenRemoved(_allowedTokenAddress);
    }

    function requestSwap(
        address _depositTokenAddress,
        uint256 _amount,
        uint256 _minExpectedAmount
    ) public allowedToken(_depositTokenAddress) whenNotPaused {
        require(_amount != 0, InvalidAmount(_amount));
        uint256 minSwapAmount = minSwapAmounts[_depositTokenAddress];
        require(_amount >= minSwapAmount, InsufficientAmount(_amount, minSwapAmount));

        IERC20(_depositTokenAddress).safeTransferFrom(msg.sender, address(this), _amount);
        Request memory request = _addSwapRequest(_depositTokenAddress, _amount, _minExpectedAmount);

        emit SwapRequestCreated(
            request.id,
            request.provider,
            request.token,
            request.amount,
            request.minExpectedAmount
        );
    }

    function _addSwapRequest(
        address _tokenAddress,
        uint256 _amount,
        uint256 _minExpectedAmount
    ) internal returns (Request memory swapRequest) {
        uint256 id = swapRequestsCounter;
        swapRequest = Request({
            id: id,
            provider: msg.sender,
            state: State.CREATED,
            amount: _amount,
            token: _tokenAddress,
            minExpectedAmount: _minExpectedAmount
        });
        swapRequests[id] = swapRequest;

        unchecked {swapRequestsCounter++;}

        return swapRequest;
    }
}
