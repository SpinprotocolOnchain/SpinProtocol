// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import { SpinWethVault } from "../../src/SpinWethVault.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

contract SpinWethVaultTest {
    function testAcceptsAndAccountsAnExactRouterDeposit() external {
        MockWETH weth = new MockWETH();
        address creatorTreasury = address(0xA11CE);
        address spinHolderJackpot = address(0xB0B);
        address buybackReserve = address(0xC0DE);
        SpinWethVault vault = new SpinWethVault(
            weth, address(this), creatorTreasury, spinHolderJackpot, buybackReserve
        );
        weth.mint(address(this), 7 ether);
        weth.approve(address(vault), 7 ether);

        vault.fundJackpot(7 ether);

        require(vault.accountedPot() == 6.825 ether, "project pot not recorded");
        require(weth.balanceOf(address(vault)) == 6.825 ether, "project asset missing");
        require(weth.balanceOf(creatorTreasury) == 0.07 ether, "treasury allocation missing");
        require(weth.balanceOf(spinHolderJackpot) == 0.07 ether, "SPIN jackpot allocation missing");
        require(weth.balanceOf(buybackReserve) == 0.035 ether, "buyback allocation missing");
    }

    function testRejectsAThirdPartyDepositCall() external {
        MockWETH weth = new MockWETH();
        SpinWethVault vault = new SpinWethVault(
            weth, address(0xBEEF), address(0xA11CE), address(0xB0B), address(0xC0DE)
        );

        (bool ok,) = address(vault).call(abi.encodeCall(vault.fundJackpot, (1)));
        require(!ok, "third party could fund as router");
    }

    function testRejectsMergedFeeDestinations() external {
        MockWETH weth = new MockWETH();
        try this.deployWithMergedDestinations(weth) {
            revert("merged destinations accepted");
        } catch { }
    }

    function deployWithMergedDestinations(MockWETH weth) external {
        new SpinWethVault(
            weth, address(0xBEEF), address(0xA11CE), address(0xA11CE), address(0xC0DE)
        );
    }
}
