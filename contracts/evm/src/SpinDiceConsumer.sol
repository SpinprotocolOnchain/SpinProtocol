// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IDiceEntropyConsumer } from "./interfaces/IDiceEntropyConsumer.sol";
import { IDiceEntropyV2 } from "./interfaces/IDiceEntropyV2.sol";
import { IWETH } from "./interfaces/IWETH.sol";
import { SafeERC20 } from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";

/// @notice Stores Dice randomness for a SPIN vault without holding jackpot funds.
/// @dev The vault is the only caller that can request or refund entropy. Dice is
/// the only caller that can resolve a request through its callback.
contract SpinDiceConsumer is IDiceEntropyConsumer {
    using SafeERC20 for IWETH;
    enum RequestStatus {
        None,
        Pending,
        Resolved
    }

    struct Request {
        bytes32 context;
        bytes32 randomWord;
        RequestStatus status;
    }

    error OnlyVault();
    error OnlyEntropy();
    error InvalidConfiguration();
    error UnexpectedProvider();
    error IncorrectFee(uint256 supplied, uint256 required);
    error UnknownRequest(uint64 sequenceNumber);
    error RequestAlreadyResolved(uint64 sequenceNumber);
    error InsufficientRefundBalance(uint256 available, uint256 required);

    event RandomnessRequested(uint64 indexed sequenceNumber, bytes32 indexed context);
    event RandomnessResolved(
        uint64 indexed sequenceNumber, bytes32 indexed context, bytes32 randomWord
    );
    event RandomnessRefunded(uint64 indexed sequenceNumber, bytes32 indexed context);

    address public immutable vault;
    IDiceEntropyV2 public immutable entropy;
    address public immutable provider;
    uint32 public immutable callbackGasLimit;

    mapping(uint64 sequenceNumber => Request request) private _requests;

    constructor(
        address vault_,
        IDiceEntropyV2 entropy_,
        address provider_,
        uint32 callbackGasLimit_
    ) {
        if (vault_ == address(0) || address(entropy_) == address(0) || provider_ == address(0)) {
            revert InvalidConfiguration();
        }
        vault = vault_;
        entropy = entropy_;
        provider = provider_;
        callbackGasLimit = callbackGasLimit_;
    }

    function requestRandomness(bytes32 context, bytes32 userRandomness)
        external
        payable
        onlyVault
        returns (uint64 sequenceNumber)
    {
        uint256 fee = entropy.getFeeV2(provider, callbackGasLimit);
        if (msg.value != fee) revert IncorrectFee(msg.value, fee);

        sequenceNumber = entropy.requestV2{ value: fee }(provider, userRandomness, callbackGasLimit);
        _requests[sequenceNumber] =
            Request({ context: context, randomWord: bytes32(0), status: RequestStatus.Pending });
        emit RandomnessRequested(sequenceNumber, context);
    }

    /// @notice Dice v10's external callback entry point.
    function _entropyCallback(uint64 sequenceNumber, address provider_, bytes32 randomNumber)
        external
        override
    {
        if (msg.sender != address(entropy)) revert OnlyEntropy();
        if (provider_ != provider) revert UnexpectedProvider();

        Request storage request = _requests[sequenceNumber];
        if (request.status == RequestStatus.None) revert UnknownRequest(sequenceNumber);
        if (request.status == RequestStatus.Resolved) {
            revert RequestAlreadyResolved(sequenceNumber);
        }

        request.randomWord = randomNumber;
        request.status = RequestStatus.Resolved;
        emit RandomnessResolved(sequenceNumber, request.context, randomNumber);
    }

    /// @notice Refunds an unrevealed Dice request after Dice's own delay has elapsed.
    function refundRandomness(uint64 sequenceNumber) external onlyVault {
        Request storage request = _requests[sequenceNumber];
        if (request.status == RequestStatus.None) revert UnknownRequest(sequenceNumber);
        if (request.status == RequestStatus.Resolved) {
            revert RequestAlreadyResolved(sequenceNumber);
        }

        bytes32 context = request.context;
        entropy.refundRequest(provider, sequenceNumber);
        delete _requests[sequenceNumber];
        emit RandomnessRefunded(sequenceNumber, context);
    }

    function wrapRefund(IWETH settlementAsset, address recipient, uint256 amount)
        external
        onlyVault
    {
        if (address(this).balance < amount) {
            revert InsufficientRefundBalance(address(this).balance, amount);
        }
        settlementAsset.deposit{ value: amount }();
        settlementAsset.safeTransfer(recipient, amount);
    }

    function getRequest(uint64 sequenceNumber) external view returns (Request memory) {
        return _requests[sequenceNumber];
    }

    modifier onlyVault() {
        if (msg.sender != vault) revert OnlyVault();
        _;
    }

    receive() external payable { }
}
