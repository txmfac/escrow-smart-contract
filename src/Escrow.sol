// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract EscrowContract {
  error NotBuyer();
  error NotSeller();
  error NotArbiter();
  error NotEscrowActor();
  error BadState();
  error ZeroAddress();
  error ZeroAmount();
  error TransferFailed();
  error CantRefundYet();
  error TimeoutTooLow();

  event EscrowCreated(uint256 indexed id, address indexed buyer, address indexed seller, address arbiter);
  event EscrowAccepted(uint256 indexed id);
  event EscrowCanceled(uint256 indexed id);
  event EscrowReleased(uint256 indexed id);
  event EscrowRefunded(uint256 indexed id);
  event EscrowDisputed(uint256 indexed id);

  enum EscrowState {
    Created,
    Funded,
    Released,
    Refunded,
    Disputed,
    Canceled
  }

  struct Escrow {
    address buyer;
    address seller;
    address arbiter;
    uint256 price;
    uint256 created;
    uint256 timeout;
    EscrowState state;
  }

  uint256 public escrowId;

  mapping(uint256 => Escrow) public escrows;

  modifier onlyBuyer(uint256 id) {
    if (msg.sender != escrows[id].buyer) revert NotBuyer();
    _;
  }

  modifier onlySeller(uint256 id) {
    if (msg.sender != escrows[id].seller) revert NotSeller();
    _;
  }

  modifier onlyArbiter(uint256 id) {
    if (msg.sender != escrows[id].arbiter) revert NotArbiter();
    _;
  }

  function createEscrow(address payable _seller, address _arbiter, uint256 _timeout) external payable returns (uint256 id) {
    if (_seller == address(0) || _arbiter == address(0)) revert ZeroAddress();
    if (msg.value == 0) revert ZeroAmount();
    if (_timeout < 3 days) revert TimeoutTooLow();

    id = escrowId++;

    escrows[id] = Escrow({
        buyer: msg.sender,
        seller: _seller,
        arbiter: _arbiter,
        price: msg.value,
        timeout: _timeout,
        created: 0,
        state: EscrowState.Created
    });

    emit EscrowCreated(id, msg.sender, _seller, _arbiter);
  }

  function acceptEscrow(uint256 _id) external onlySeller(_id) {
    Escrow storage e = escrows[_id];

    if (e.state != EscrowState.Created) revert BadState();
    e.state = EscrowState.Funded;
    e.created = block.timestamp;

    emit EscrowAccepted(_id);
  }

  function cancelEscrow(uint256 _id) external onlyBuyer(_id) {
    Escrow storage e = escrows[_id];

    if (e.state != EscrowState.Created) revert BadState();
    e.state = EscrowState.Canceled;
    e.price = 0;

    (bool ok,) = msg.sender.call{value: e.price}("");
    if (!ok) revert TransferFailed();

    emit EscrowCanceled(_id);
  }

  function releaseEscrow(uint256 _id) external onlyBuyer(_id) {
    Escrow storage e = escrows[_id];

    if (e.state != EscrowState.Funded) revert BadState();
    e.state = EscrowState.Released;
    (bool ok,) = e.seller.call{value: e.price}("");
    if (!ok) revert TransferFailed();

    emit EscrowReleased(_id);
  }

  function refundEscrow(uint256 _id) external onlyBuyer(_id) {
    Escrow storage e = escrows[_id];

    if (block.timestamp < e.created + e.timeout) revert CantRefundYet();
    if (e.state != EscrowState.Funded) revert BadState();
    e.state = EscrowState.Refunded;
    (bool ok,) = msg.sender.call{value: e.price}("");
    if (!ok) revert TransferFailed();

    emit EscrowRefunded(_id);
  }

  function disputeEscrow(uint256 _id) external {
    Escrow storage e = escrows[_id];

    if (msg.sender != e.buyer && msg.sender != e.seller) revert NotEscrowActor();
    if (e.state != EscrowState.Funded) revert BadState();
    e.state = EscrowState.Disputed;

    emit EscrowDisputed(_id);
  }

  function arbiterDecisionRelease(uint256 _id) external onlyArbiter(_id) {
    Escrow storage e = escrows[_id];

    if (e.state != EscrowState.Disputed) revert BadState();
    e.state = EscrowState.Released;
    (bool ok,) = e.seller.call{value: e.price}("");
    if (!ok) revert TransferFailed();

    emit EscrowReleased(_id);
  }

  function arbiterDecisionRefund(uint256 _id) external onlyArbiter(_id) {
    Escrow storage e = escrows[_id];

    if (e.state != EscrowState.Disputed) revert BadState();
    e.state = EscrowState.Refunded;
    (bool ok,) = e.buyer.call{value: e.price}("");
    if (!ok) revert TransferFailed();

    emit EscrowRefunded(_id);
  }
}
