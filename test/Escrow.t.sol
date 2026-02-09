// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Escrow.sol";

contract EscrowContractTest is Test {
    EscrowContract escrow;

    address buyer   = address(0xBEEF);
    address seller  = address(0xCAFE);
    address arbiter = address(0xABCD);
    address rando   = address(0xD00D);

    uint256 constant PRICE   = 1 ether;
    uint256 constant TIMEOUT = 7 days;

    function setUp() public {
        escrow = new EscrowContract();
        vm.txGasPrice(0);

        vm.deal(buyer, 10 ether);
        vm.deal(seller, 10 ether);
        vm.deal(arbiter, 10 ether);
        vm.deal(rando, 10 ether);
    }

    // -------- helpers --------

    function _create() internal returns (uint256 id) {
        vm.prank(buyer);
        id = escrow.createEscrow{value: PRICE}(payable(seller), arbiter, TIMEOUT);
    }

    function _createAndAccept() internal returns (uint256 id) {
        id = _create();
        vm.prank(seller);
        escrow.acceptEscrow(id);
    }

    // -------- create --------

    function testCreateEscrowStoresDataAndHoldsEth() public {
        uint256 id = _create();

        (
            address b,
            address s,
            address a,
            uint256 price,
            uint256 startedAt,
            uint256 timeout,
            EscrowContract.EscrowState state
        ) = escrow.escrows(id);

        assertEq(b, buyer);
        assertEq(s, seller);
        assertEq(a, arbiter);
        assertEq(price, PRICE);
        assertEq(startedAt, 0);
        assertEq(timeout, TIMEOUT);
        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Created));

        assertEq(address(escrow).balance, PRICE);
    }

    function testCreateEscrowRevertsZeroAddress() public {
        vm.prank(buyer);
        vm.expectRevert(EscrowContract.ZeroAddress.selector);
        escrow.createEscrow{value: PRICE}(payable(address(0)), arbiter, TIMEOUT);

        vm.prank(buyer);
        vm.expectRevert(EscrowContract.ZeroAddress.selector);
        escrow.createEscrow{value: PRICE}(payable(seller), address(0), TIMEOUT);
    }

    function testCreateEscrowRevertsZeroAmount() public {
        vm.prank(buyer);
        vm.expectRevert(EscrowContract.ZeroAmount.selector);
        escrow.createEscrow{value: 0}(payable(seller), arbiter, TIMEOUT);
    }

    function testCreateEscrowRevertsWrongTimeout() public {
        vm.prank(buyer);
        vm.expectRevert(EscrowContract.WrongTimeout.selector);
        escrow.createEscrow{value: PRICE}(payable(seller), arbiter, 2 days);

        vm.prank(buyer);
        vm.expectRevert(EscrowContract.WrongTimeout.selector);
        escrow.createEscrow{value: PRICE}(payable(seller), arbiter, 31 days);
    }

    // -------- accept --------

    function testSellerAcceptsAndStartsTimer() public {
        uint256 id = _create();

        vm.prank(seller);
        escrow.acceptEscrow(id);

        (, , , , uint256 startedAt, , EscrowContract.EscrowState state) = escrow.escrows(id);

        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Funded));
        assertTrue(startedAt > 0);
    }

    function testAcceptRevertsIfNotSeller() public {
        uint256 id = _create();

        vm.prank(buyer);
        vm.expectRevert(EscrowContract.NotSeller.selector);
        escrow.acceptEscrow(id);
    }

    function testAcceptRevertsIfBadState() public {
        uint256 id = _createAndAccept();

        vm.prank(seller);
        vm.expectRevert(EscrowContract.BadState.selector);
        escrow.acceptEscrow(id);
    }

    function testEscrowNotFoundReverts() public {
        vm.prank(seller);
        vm.expectRevert(EscrowContract.EscrowNotFound.selector);
        escrow.acceptEscrow(999);
    }

    // -------- cancel --------

    function testBuyerCanCancelBeforeAcceptAndGetsRefund() public {
        uint256 id = _create();

        uint256 buyerBefore = buyer.balance;

        vm.prank(buyer);
        escrow.cancelEscrow(id);

        (, , , uint256 price, , , EscrowContract.EscrowState state) = escrow.escrows(id);

        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Canceled));
        assertEq(price, 0);
        assertEq(address(escrow).balance, 0);
        assertEq(buyer.balance, buyerBefore + PRICE);
    }

    function testCancelRevertsIfNotBuyer() public {
        uint256 id = _create();

        vm.prank(seller);
        vm.expectRevert(EscrowContract.NotBuyer.selector);
        escrow.cancelEscrow(id);
    }

    function testCancelRevertsIfBadState() public {
        uint256 id = _createAndAccept();

        vm.prank(buyer);
        vm.expectRevert(EscrowContract.BadState.selector);
        escrow.cancelEscrow(id);
    }

    // -------- release --------

    function testBuyerReleasePaysSeller() public {
        uint256 id = _createAndAccept();

        uint256 sellerBefore = seller.balance;

        vm.prank(buyer);
        escrow.releaseEscrow(id);

        (, , , , , , EscrowContract.EscrowState state) = escrow.escrows(id);

        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Released));
        assertEq(address(escrow).balance, 0);
        assertEq(seller.balance, sellerBefore + PRICE);
    }

    function testReleaseRevertsIfNotBuyer() public {
        uint256 id = _createAndAccept();

        vm.prank(seller);
        vm.expectRevert(EscrowContract.NotBuyer.selector);
        escrow.releaseEscrow(id);
    }

    function testReleaseRevertsIfBadState() public {
        uint256 id = _create();

        vm.prank(buyer);
        vm.expectRevert(EscrowContract.BadState.selector);
        escrow.releaseEscrow(id);
    }

    // -------- refund --------

    function testRefundRevertsIfTooEarly() public {
        uint256 id = _createAndAccept();

        vm.prank(buyer);
        vm.expectRevert(EscrowContract.CantRefundYet.selector);
        escrow.refundEscrow(id);
    }

    function testRefundAfterTimeoutPaysBuyer() public {
        uint256 id = _createAndAccept();

        uint256 buyerBefore = buyer.balance;

        // jump forward past startedAt + timeout
        vm.warp(block.timestamp + TIMEOUT + 1);

        vm.prank(buyer);
        escrow.refundEscrow(id);

        (, , , , , , EscrowContract.EscrowState state) = escrow.escrows(id);

        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Refunded));
        assertEq(address(escrow).balance, 0);
        assertEq(buyer.balance, buyerBefore + PRICE);
    }

    // -------- dispute + arbiter --------

    function testBuyerOrSellerCanDispute() public {
        uint256 id = _createAndAccept();

        vm.prank(seller);
        escrow.disputeEscrow(id);

        (, , , , , , EscrowContract.EscrowState state) = escrow.escrows(id);
        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Disputed));
    }

    function testDisputeRevertsIfNotActor() public {
        uint256 id = _createAndAccept();

        vm.prank(rando);
        vm.expectRevert(EscrowContract.NotEscrowActor.selector);
        escrow.disputeEscrow(id);
    }

    function testArbiterCanResolveRelease() public {
        uint256 id = _createAndAccept();

        vm.prank(buyer);
        escrow.disputeEscrow(id);

        uint256 sellerBefore = seller.balance;

        vm.prank(arbiter);
        escrow.arbiterDecisionRelease(id);

        (, , , , , , EscrowContract.EscrowState state) = escrow.escrows(id);

        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Released));
        assertEq(address(escrow).balance, 0);
        assertEq(seller.balance, sellerBefore + PRICE);
    }

    function testArbiterCanResolveRefund() public {
        uint256 id = _createAndAccept();

        vm.prank(seller);
        escrow.disputeEscrow(id);

        uint256 buyerBefore = buyer.balance;

        vm.prank(arbiter);
        escrow.arbiterDecisionRefund(id);

        (, , , , , , EscrowContract.EscrowState state) = escrow.escrows(id);

        assertEq(uint256(state), uint256(EscrowContract.EscrowState.Refunded));
        assertEq(address(escrow).balance, 0);
        assertEq(buyer.balance, buyerBefore + PRICE);
    }

    function testArbiterDecisionRevertsIfNotArbiter() public {
        uint256 id = _createAndAccept();

        vm.prank(buyer);
        escrow.disputeEscrow(id);

        vm.prank(buyer);
        vm.expectRevert(EscrowContract.NotArbiter.selector);
        escrow.arbiterDecisionRelease(id);
    }

    function testArbiterDecisionRevertsIfNotDisputed() public {
        uint256 id = _createAndAccept();

        vm.prank(arbiter);
        vm.expectRevert(EscrowContract.BadState.selector);
        escrow.arbiterDecisionRefund(id);
    }

    // -------- receive / fallback --------

    function testDirectEthSendRevertsReceive() public {
        vm.expectRevert(EscrowContract.DirectEthNotAllowed.selector);
        (bool ok,) = address(escrow).call{value: 0.1 ether}("");
        ok; // silence unused warning
    }

    function testDirectEthSendRevertsFallback() public {
        vm.expectRevert(EscrowContract.DirectEthNotAllowed.selector);
        (bool ok,) = address(escrow).call{value: 0.1 ether}(hex"12345678");
        ok;
    }
}
