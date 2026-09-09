// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinDiceConsumer } from "../../src/SpinDiceConsumer.sol";
import { MockDiceEntropyV2 } from "../mocks/MockDiceEntropyV2.sol";

contract SpinDiceConsumerTest {
    address private constant VAULT = address(0xBEEF);
    address private constant PROVIDER = address(0xCAFE);
    uint128 private constant FEE = 0;

    function testOnlyVaultCanRequest() external {
        (SpinDiceConsumer consumer,) = _deploy(VAULT);
        (bool ok,) = address(consumer)
            .call(abi.encodeCall(consumer.requestRandomness, (bytes32("round"), bytes32("seed"))));
        require(!ok, "non-vault request succeeded");
    }

    function testOnlyOracleCanResolve() external {
        (SpinDiceConsumer consumer,) = _deploy(VAULT);
        (bool ok,) = address(consumer)
            .call(abi.encodeCall(consumer._entropyCallback, (1, PROVIDER, bytes32("word"))));
        require(!ok, "non-oracle callback succeeded");
    }

    function testUnknownSequenceIsRejectedByOracle() external {
        (, MockDiceEntropyV2 entropy) = _deploy(VAULT);
        (bool ok,) = address(entropy)
            .call(abi.encodeWithSelector(entropy.reveal.selector, 999, bytes32("word")));
        require(!ok, "unknown request callback succeeded");
    }

    function testStoresOnlyOracleDeliveredRandomnessForTheSealedContext() external {
        (SpinDiceConsumer consumer, MockDiceEntropyV2 entropy) = _deploy(address(this));
        uint64 sequenceNumber = consumer.requestRandomness(bytes32("round-7"), bytes32("user-seed"));

        entropy.reveal(sequenceNumber, bytes32("dice-word"));
        SpinDiceConsumer.Request memory request = consumer.getRequest(sequenceNumber);

        require(request.context == bytes32("round-7"), "context changed");
        require(request.randomWord == bytes32("dice-word"), "wrong random word");
        require(
            request.status == SpinDiceConsumer.RequestStatus.Resolved, "request was not resolved"
        );
    }

    function _deploy(address vault)
        private
        returns (SpinDiceConsumer consumer, MockDiceEntropyV2 entropy)
    {
        entropy = new MockDiceEntropyV2(FEE);
        consumer = new SpinDiceConsumer(vault, entropy, PROVIDER, 200_000);
    }
}
