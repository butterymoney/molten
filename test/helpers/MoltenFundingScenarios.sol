// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC20PresetMinterPauser} from "openzeppelin/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import {MoltenFunding} from "../../src/MoltenFunding.sol";
import {MToken} from "../../src/MToken.sol";
import {ERC20VotesMintable} from "./ERC20VotesMintable.sol";

abstract contract MoltenFundingTestBase is Test {
    ERC20VotesMintable public daoToken;
    MoltenFunding public moltenFunding;
    address public daoTreasuryAddress = address(0x1);

    address public candidateAddress = address(0x2);

    ERC20PresetMinterPauser public depositToken; // Used for minting.
    address public depositorAddress = address(0x3);

    MToken public mToken;

    function setUp() public virtual {
        daoToken = new ERC20VotesMintable("DAO governance token", "GT");
        depositToken = new ERC20PresetMinterPauser("Stable token", "BAI");
        vm.prank(candidateAddress);
        moltenFunding = new MoltenFunding(
            address(daoToken),
            365 days,
            address(depositToken),
            daoTreasuryAddress
        );
        mToken = moltenFunding.mToken();
        vm.label(daoTreasuryAddress, "DAO treasury");
        vm.label(depositorAddress, "Depositor");
        vm.label(address(moltenFunding), "Molten fundraiser");
    }
}

abstract contract DepositTestBase is MoltenFundingTestBase {
    function setUp() public virtual override {
        super.setUp();

        depositToken.mint(depositorAddress, 1000 * 10**18);
        vm.prank(depositorAddress);
        depositToken.approve(address(moltenFunding), 1000 * 10**18);

        vm.prank(depositorAddress);
        moltenFunding.deposit(1000 * 10**18);
    }
}

abstract contract ExchangeTestBase is DepositTestBase {
    function setUp() public virtual override {
        super.setUp();

        daoToken.mint(daoTreasuryAddress, 4242 * 10**18);
        vm.prank(daoTreasuryAddress);
        daoToken.approve(address(moltenFunding), type(uint256).max);

        vm.prank(daoTreasuryAddress);
        moltenFunding.exchange(20);
    }
}

abstract contract LiquidationTestBase is ExchangeTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(depositorAddress);
        moltenFunding.claimMTokens();
        skip(365 days);
        moltenFunding.liquidate();
    }
}
