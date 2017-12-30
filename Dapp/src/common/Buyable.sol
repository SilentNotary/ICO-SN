pragma solidity ^0.4.18;

// Interface for contracts with buying functionality, for example, crowdsales.
contract Buyable {
  function buy (address receiver) public payable;
}
