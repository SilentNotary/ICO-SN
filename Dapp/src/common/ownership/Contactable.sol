pragma solidity ^0.4.13;

import './Ownable.sol';

 /// @title Contactable contract - basic version of a contactable contract
contract Contactable is Ownable {
     string public contactInformation;

     function setContactInformation(string info) onlyOwner{
         contactInformation = info;
     }
}
