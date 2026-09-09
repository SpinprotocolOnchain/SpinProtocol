// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { IDiceEntropyConsumer } from "../../src/interfaces/IDiceEntropyConsumer.sol";
import { IDiceEntropyV2 } from "../../src/interfaces/IDiceEntropyV2.sol";

contract MockDiceEntropyV2 is IDiceEntropyV2 {
    uint128 public immutable fee;
    uint64 private _nextSequence = 1;

    mapping(uint64 sequenceNumber => address requester) public requester;
    mapping(uint64 sequenceNumber => address provider) public requestProvider;
    mapping(uint64 sequenceNumber => uint256) public requestFee;

    constructor(uint128 fee_) {
        fee = fee_;
    }

    function requestV2(address provider, bytes32, uint32)
        external
        payable
        returns (uint64 sequenceNumber)
    {
        require(msg.value == fee, "fee");
        sequenceNumber = _nextSequence++;
        requester[sequenceNumber] = msg.sender;
        requestProvider[sequenceNumber] = provider;
        requestFee[sequenceNumber] = msg.value;
    }

    function getFeeV2(address, uint32) external view returns (uint128) {
        return fee;
    }

    function refundRequest(address provider, uint64 sequenceNumber) external {
        require(msg.sender == requester[sequenceNumber], "requester");
        require(provider == requestProvider[sequenceNumber], "provider");
        uint256 paidFee = requestFee[sequenceNumber];
        delete requester[sequenceNumber];
        delete requestProvider[sequenceNumber];
        delete requestFee[sequenceNumber];
        (bool sent,) = msg.sender.call{ value: paidFee }("");
        require(sent, "refund");
    }

    function reveal(uint64 sequenceNumber, bytes32 randomWord) external {
        IDiceEntropyConsumer(requester[sequenceNumber])
            ._entropyCallback(sequenceNumber, requestProvider[sequenceNumber], randomWord);
    }

    receive() external payable { }
}
