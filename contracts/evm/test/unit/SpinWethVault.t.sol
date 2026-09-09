// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinRoundBook } from "../../src/SpinRoundBook.sol";

import { SpinWethVault } from "../../src/SpinWethVault.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

interface VaultVm {
    function roll(uint256 height) external;
}

contract SpinWethVaultTest {
    VaultVm private constant vm = VaultVm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testCutoffIsInclusiveAndUnknownRoundCannotReceiveFunds() external {
        MockWETH weth = new MockWETH();
        SpinWethVault vault = new SpinWethVault(
            _book(),
            weth,
            address(this),
            address(this),
            address(0xA11CE),
            address(0xB0B),
            address(0xC0DE)
        );
        weth.mint(address(this), 3 ether);
        weth.approve(address(vault), 3 ether);
        (bool unknown,) = address(vault).call(abi.encodeCall(vault.fundRoundJackpot, (1, 1 ether)));
        require(!unknown, "unknown round funded");
        vm.roll(20);
        (bool earlySeal,) = address(vault).call(abi.encodeCall(vault.sealRoundPot, (0)));
        require(!earlySeal, "sealed during final funding block");
        vault.fundRoundJackpot(0, 1 ether);
        vm.roll(21);
        (bool late,) = address(vault).call(abi.encodeCall(vault.fundRoundJackpot, (0, 1 ether)));
        require(!late, "late funds accepted before seal");
        vault.sealRoundPot(0);
        vault.sealRoundPot(0);
        require(vault.roundPot(0) == 0.975 ether, "seal changed pot");
    }

    function testFuzzDepositsPreserveEveryWei(uint96 amount) external {
        MockWETH weth = new MockWETH();
        SpinWethVault vault = new SpinWethVault(
            _book(),
            weth,
            address(this),
            address(this),
            address(0xA11CE),
            address(0xB0B),
            address(0xC0DE)
        );
        weth.mint(address(this), amount);
        weth.approve(address(vault), amount);
        vault.fundRoundJackpot(0, amount);
        require(vault.roundPot(0) == vault.accountedPot(), "round accounting differs");
        require(weth.balanceOf(address(vault)) == vault.accountedPot(), "unbacked pot");
        require(
            weth.balanceOf(address(vault)) + weth.balanceOf(address(0xA11CE))
                    + weth.balanceOf(address(0xB0B)) + weth.balanceOf(address(0xC0DE)) == amount,
            "wei lost"
        );
    }

    function testAcceptsAndAccountsAnExactRouterDeposit() external {
        MockWETH weth = new MockWETH();
        address creatorTreasury = address(0xA11CE);
        address spinHolderJackpot = address(0xB0B);
        address buybackReserve = address(0xC0DE);
        SpinWethVault vault = new SpinWethVault(
            _book(),
            weth,
            address(this),
            address(this),
            creatorTreasury,
            spinHolderJackpot,
            buybackReserve
        );
        weth.mint(address(this), 7 ether);
        weth.approve(address(vault), 7 ether);

        vault.fundRoundJackpot(0, 7 ether);

        require(vault.accountedPot() == 6.825 ether, "project pot not recorded");
        require(weth.balanceOf(address(vault)) == 6.825 ether, "project asset missing");
        require(weth.balanceOf(creatorTreasury) == 0.07 ether, "treasury allocation missing");
        require(weth.balanceOf(spinHolderJackpot) == 0.07 ether, "SPIN jackpot allocation missing");
        require(weth.balanceOf(buybackReserve) == 0.035 ether, "buyback allocation missing");
    }

    function testRejectsAThirdPartyDepositCall() external {
        MockWETH weth = new MockWETH();
        SpinWethVault vault = new SpinWethVault(
            _book(),
            weth,
            address(this),
            address(0xBEEF),
            address(0xA11CE),
            address(0xB0B),
            address(0xC0DE)
        );

        (bool ok,) = address(vault).call(abi.encodeCall(vault.fundRoundJackpot, (0, 1)));
        require(!ok, "third party could fund as router");
    }

    function testRejectsMergedFeeDestinations() external {
        MockWETH weth = new MockWETH();
        try this.deployWithMergedDestinations(weth) {
            revert("merged destinations accepted");
        } catch { }
    }

    function _book() private returns (SpinRoundBook book) {
        book = new SpinRoundBook(
            address(this), address(this), address(this), address(this), bytes32("policy"), 32
        );
        book.configureNextRound(
            SpinRoundBook.RoundConfiguration({
                configurationHash: bytes32("config"),
                qualificationStartBlock: 10,
                qualificationEndBlock: 20,
                finalityBlocks: 3,
                reviewBlocks: 5,
                snapshotExpiryBlocks: 20,
                minimumPayout: 1 ether,
                maximumWinners: 3
            })
        );
    }

    function deployWithMergedDestinations(MockWETH weth) external {
        new SpinWethVault(
            _book(),
            weth,
            address(this),
            address(0xBEEF),
            address(0xA11CE),
            address(0xA11CE),
            address(0xC0DE)
        );
    }
}
