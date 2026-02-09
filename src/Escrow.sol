// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract EscrowContract {
  error NotBuyer();
  error NotSeller();
  error BadState();
  error ZeroAddress();
  error ZeroAmount();
  error TransferFailed();

  enum EscrowState {
    Funded,
    Released,
    Refunded,
    Conflict,
    Cancelled
  }

  struct Escrow {
    address buyer;
    address seller;
    address arbriter;
    uint256 price;
    uint256 created;
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

  function createEscrow(address payable _seller, address _arbriter) external payable returns (uint256 id) {
    if (_seller == address(0) || _arbriter == address(0)) revert ZeroAddress();
    if (msg.value == 0) revert ZeroAmount();

    id = escrowId++;

    escrows[id] = Escrow({
        buyer: msg.sender,
        seller: _seller,
        arbriter: _arbriter,
        price: msg.value,
        created: block.timestamp,
        state: EscrowState.Funded
    });
  }

  function releaseEscrow(uint256 _id) external onlyBuyer(_id) {
    Escrow storage e = escrows[_id];

    if (e.state != EscrowState.Funded) revert BadState();
    e.state = EscrowState.Released;
    (bool ok,) = e.seller.call{value: e.price}("");
    if (!ok) revert TransferFailed();
  }

  function refundEscrow(uint256 _id) external onlyBuyer(_id) {
    Escrow storage e = escrows[_id];

    if (e.state != EscrowState.Funded) revert BadState();
    e.state = EscrowState.Refunded;
    (bool ok,) = msg.sender.call{value: e.price}("");
    if (!ok) revert TransferFailed();
  }
}
