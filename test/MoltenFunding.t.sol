// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {ERC20PresetMinterPauser} from "openzeppelin/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import {MoltenFunding} from "../src/MoltenFunding.sol";
import {MToken} from "../src/MToken.sol";
import {ERC20VotesMintable} from "./helpers/ERC20VotesMintable.sol";

abstract contract MoltenFundingTestBase is Test {
    ERC20VotesMintable public daoToken;
    MoltenFunding public moltenFunding;
    address public daoTreasuryAddress = address(0x1);

    address public candidateAddress = address(0x2);

    ERC20PresetMinterPauser public depositToken; // Used for minting.
    address public depositorAddress = address(0x3);

    MToken mToken;

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

contract MoltenFundingCreationTest is MoltenFundingTestBase {
    function testConstructor() public {
        assertEq(moltenFunding.lockingDuration(), 365 days);
    }

    function testDepositMissingFunds() public {
        depositToken.mint(depositorAddress, 1000 * 10**18);

        vm.expectRevert();
        vm.prank(depositorAddress);
        moltenFunding.deposit(1000 * 10**18);
    }

    function testExchangeMissingFunds() public {
        depositToken.mint(depositorAddress, 1000 * 10**18);
        vm.prank(depositorAddress);
        depositToken.approve(address(moltenFunding), 1000 * 10**18);
        vm.prank(depositorAddress);
        moltenFunding.deposit(1000 * 10**18);

        vm.expectRevert(bytes("ERC20: insufficient allowance"));
        vm.prank(daoTreasuryAddress);
        moltenFunding.exchange(20);
    }

    function testLiquidateBlocked() public {
        vm.expectRevert("Molten: exchange not happened");
        moltenFunding.liquidate();
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

contract DepositTest is DepositTestBase {
    function testRecordsDeposit() public {
        assertEq(moltenFunding.deposited(depositorAddress), 1000 * 10**18);
    }

    function testIncreasesTotalDeposits() public {
        depositToken.mint(address(0x234), 234 * 10**18);
        vm.prank(address(0x234));
        depositToken.approve(address(moltenFunding), 234 * 10**18);
        vm.prank(address(0x234));
        moltenFunding.deposit(234 * 10**18);

        assertEq(moltenFunding.totalDeposited(), 1234 * 10**18);
    }

    function testAllowsRefund() public {
        vm.prank(depositorAddress);
        moltenFunding.refund(1000 * 10**18);

        assertEq(moltenFunding.deposited(depositorAddress), 0);
    }

    function testBlocksTooLargeRefund() public {
        vm.expectRevert("Molten: refund amount too large");
        vm.prank(depositorAddress);
        moltenFunding.refund(1001 * 10**18);
    }

    function testClaimMTokensLocked() public {
        vm.expectRevert("Molten: exchange not happened");
        vm.prank(depositorAddress);
        moltenFunding.claimMTokens();
    }

    function testVoteBlocked() public {
        vm.expectRevert("Molten: exchange not happened");
        vm.prank(depositorAddress);
        moltenFunding.voteForLiquidation();
    }

    function testWithdrawVoteBlocked() public {
        vm.expectRevert("Molten: exchange not happened");
        vm.prank(depositorAddress);
        moltenFunding.withdrawVoteForLiquidation();
    }

    function testExchangeBlockedForNonDAO() public {
        daoToken.mint(daoTreasuryAddress, 4242 * 10**18);
        vm.prank(daoTreasuryAddress);
        daoToken.approve(address(moltenFunding), type(uint256).max);

        vm.expectRevert("Molten: exchange only by DAO");
        moltenFunding.exchange(20);
    }
}

abstract contract ExchangeTestBase is DepositTestBase {
    uint256 public initialTotalDesposits;

    function setUp() public virtual override {
        super.setUp();

        daoToken.mint(daoTreasuryAddress, 4242 * 10**18);
        vm.prank(daoTreasuryAddress);
        daoToken.approve(address(moltenFunding), type(uint256).max);

        vm.prank(daoTreasuryAddress);
        moltenFunding.exchange(20);
    }
}

contract ExchangeTest is ExchangeTestBase {
    function testSetExchangeTime() public view {
        assert(moltenFunding.exchangeTime() > 0);
    }

    function testTransfersDaoTokensToFundraiser() public {
        assertEq(daoToken.balanceOf(address(moltenFunding)), 50 * 10**18);
    }

    function testTransfersDepositsToDaoTreasury() public {
        assertEq(depositToken.balanceOf(address(moltenFunding)), 0);
        assertEq(depositToken.balanceOf(daoTreasuryAddress), 1000 * 10**18);
    }

    function testRepeatedDepositFails() public {
        vm.expectRevert("Molten: exchange happened");
        vm.prank(depositorAddress);
        moltenFunding.deposit(1000);
    }

    function testRepeatedRefundFails() public {
        vm.expectRevert("Molten: exchange happened");
        vm.prank(depositorAddress);
        moltenFunding.refund(1000);
    }

    function testRepeatedExchangeFails() public {
        vm.expectRevert("Molten: exchange happened");
        vm.prank(daoTreasuryAddress);
        moltenFunding.exchange(20);
    }

    function testMintsMTokens() public {
        assertEq(mToken.totalSupply(), (1000 / 20) * 10**18);
    }

    function testLiquidateTimeLocked() public {
        vm.expectRevert("Molten: locked");
        moltenFunding.liquidate();
    }

    function testDelegatesToCandidate() public {
        assertEq(daoToken.delegates(address(moltenFunding)), candidateAddress);
    }

    function testClaimMTokensBlockedForNonDepositor() public {
        vm.expectRevert("Molten: no mToken to claim");
        vm.prank(daoTreasuryAddress);
        moltenFunding.claimMTokens();
    }
}

contract ClaimMTokensTest is ExchangeTestBase {
    function setUp() public override {
        super.setUp();

        vm.prank(depositorAddress);
        moltenFunding.claimMTokens();
    }

    function testTransfersToDepositor() public {
        assertEq(mToken.balanceOf(address(moltenFunding)), 0);
        assertEq(
            mToken.balanceOf(depositorAddress),
            (1000 / 20) * 10**18 // 50 * 10**18
        );
    }

    function testDepositorCanTransfer() public {
        vm.prank(depositorAddress);
        mToken.transfer(address(0x4242), 50 * 10**18);
    }

    function testClaimLocked() public {
        vm.expectRevert("Molten: not liquidated");
        vm.prank(depositorAddress);
        moltenFunding.claim();
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

contract LiquidationTest is LiquidationTestBase {
    function testPausesMToken() public {
        vm.expectRevert("ERC20Pausable: token transfer while paused");
        vm.prank(depositorAddress);
        mToken.transfer(address(0x4242), 50 * 10**18);
    }

    function testClaimingBlockedForNonDepositors() public {
        vm.expectRevert("Molten: nothing to claim");
        vm.prank(daoTreasuryAddress);
        moltenFunding.claim();
    }

    function testVoteBlocked() public {
        vm.expectRevert("Molten: not locked");
        vm.prank(depositorAddress);
        moltenFunding.voteForLiquidation();
    }

    function testWithdrawVoteBlocked() public {
        vm.expectRevert("Molten: not locked");
        vm.prank(depositorAddress);
        moltenFunding.withdrawVoteForLiquidation();
    }

    function testDelegatesToNull() public {
        assertEq(daoToken.delegates(address(moltenFunding)), address(0x00));
    }
}

contract ClaimTest is LiquidationTestBase {
    function setUp() public override {
        super.setUp();

        vm.prank(depositorAddress);
        moltenFunding.claim();
    }

    function testBurnsMTokens() public {
        assertEq(mToken.balanceOf(depositorAddress), 0);
    }

    function testTransfersDaoTokens() public {
        assertEq(daoToken.balanceOf(depositorAddress), 50 * 10**18);
    }
}

contract ClaimWhenUnclaimedMTokensTest is ExchangeTestBase {
    function setUp() public virtual override {
        super.setUp();

        skip(365 days);
        moltenFunding.liquidate();
        vm.prank(depositorAddress);
        moltenFunding.claim();
    }

    function testStillTransfersDaoTokens() public {
        assertEq(daoToken.balanceOf(depositorAddress), 50 * 10**18);
    }

    function testVoteBlockedForNonDepositors() public {
        vm.expectRevert("Molten: no voting power");
        vm.prank(daoTreasuryAddress);
        moltenFunding.voteForLiquidation();
    }

    function testWithdrawVoteBlockedForNonDepositors() public {
        vm.expectRevert("Molten: no voting power");
        vm.prank(daoTreasuryAddress);
        moltenFunding.withdrawVoteForLiquidation();
    }
}

contract ClamiWhenUnclaimedMTokensAndMTokensBalancePositiveTest is
    MoltenFundingTestBase
{
    address depositorAddress2 = address(0x11);

    function setUp() public virtual override {
        super.setUp();

        depositToken.mint(depositorAddress, 1000 * 10**18);
        vm.prank(depositorAddress);
        depositToken.approve(address(moltenFunding), 1000 * 10**18);
        vm.prank(depositorAddress);
        moltenFunding.deposit(1000 * 10**18);

        depositToken.mint(depositorAddress2, 500 * 10**18);
        vm.prank(depositorAddress2);
        depositToken.approve(address(moltenFunding), 500 * 10**18);
        vm.prank(depositorAddress2);
        moltenFunding.deposit(500 * 10**18);

        daoToken.mint(daoTreasuryAddress, 4242 * 10**18);
        vm.prank(daoTreasuryAddress);
        daoToken.approve(address(moltenFunding), type(uint256).max);

        vm.prank(daoTreasuryAddress);
        moltenFunding.exchange(20); // mTokens supply = 75.

        // 2nd depositor send 10 mTokens to 1st depositor.
        vm.prank(depositorAddress2);
        moltenFunding.claimMTokens();
        vm.prank(depositorAddress2);
        mToken.transfer(depositorAddress, 10 * 10**18);

        skip(365 days);
        moltenFunding.liquidate();
    }

    function testClaimsDaoTokensForClaimedAndUnclaimedMTokens() public {
        vm.prank(depositorAddress);
        moltenFunding.claim();

        assertEq(daoToken.balanceOf(depositorAddress), 60 * 10**18);
        assertEq(mToken.totalSupply(), 15 * 10**18);
    }

    function testDoesntClaimDaoTokensForTransferredMTokens() public {
        vm.prank(depositorAddress2);
        moltenFunding.claim();

        assertEq(daoToken.balanceOf(depositorAddress2), 15 * 10**18);
        assertEq(mToken.totalSupply(), 60 * 10**18);
    }
}

contract VoteTest is ExchangeTestBase {
    function setUp() public virtual override {
        super.setUp();

        vm.prank(depositorAddress);
        moltenFunding.voteForLiquidation();
    }

    function testUpdatesTotals() public {
        assertEq(
            moltenFunding.totalVotesForLiquidation(),
            moltenFunding.totalDeposited()
        );
    }

    function testEnablesLiquidation() public {
        moltenFunding.liquidate();

        vm.prank(depositorAddress);
        moltenFunding.claim();
    }

    function testWithdrawDisablesLiquidation() public {
        vm.prank(depositorAddress);
        moltenFunding.withdrawVoteForLiquidation();

        assertEq(moltenFunding.totalVotesForLiquidation(), 0);
        vm.expectRevert("Molten: locked");
        moltenFunding.liquidate();
    }
}