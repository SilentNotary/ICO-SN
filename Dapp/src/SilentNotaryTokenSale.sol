pragma solidity ^0.4.18;

import 'common/SafeMath.sol';
import 'common/Buyable.sol';
import 'common/token/ERC20.sol';
import 'common/ownership/Ownable.sol';

 /// @title SilentNotary token sale contract
contract SilentNotaryTokenSale is Ownable, SafeMath, Buyable {

   /// State machine
   /// Preparing: Waiting for ICO start
   /// Selling: Active sale
   /// ProlongedSelling: Prolonged active sale
   /// TokenShortage: ICO period isn't over yet, but there are no tokens on the contract
   /// Finished: ICO has finished
  enum Status {Unknown, Preparing, Selling, ProlongedSelling, TokenShortage, Finished}

  /// A new investment was made
  event Invested(address investor, uint weiAmount, uint tokenAmount);

  /// Contract owner withdrew some tokens to team wallet
  event Withdraw(uint tokenAmount);

  /// Token unit price changed
  event TokenPriceChanged(uint newTokenPrice);

  /// SNTR token address
  ERC20 public token;

  /// wallet address to transfer invested ETH
  address public ethMultisigWallet;

  /// wallet address to withdraw unused tokens
  address public tokenMultisigWallet;

  /// ICO start time
  uint public startTime;

  /// ICO duration in seconds
  uint public duration;

  /// Prolonged ICO duration in seconds, 0 if no prolongation is planned
  uint public prolongedDuration;

  /// Token price in wei
  uint public tokenPrice;

  /// Minimal investment amount in wei
  uint public minInvestment;

  /// List of addresses allowed to send ETH to this contract, empty if anyone is allowed
  address[] public allowedSenders;

  /// The number of tokens already sold through this contract
  uint public tokensSoldAmount = 0;

  ///  How many wei of funding we have raised
  uint public weiRaisedAmount = 0;

  ///  How many distinct addresses have invested
  uint public investorCount = 0;

  ///  Was prolongation permitted by owner or not
  bool public prolongationPermitted;

  ///  How much ETH each address has invested to this crowdsale
  mapping (address => uint256) public investedAmountOf;

  ///  How much tokens this crowdsale has credited for each investor address
  mapping (address => uint256) public tokenAmountOf;

  /// Multiplier for token value
  uint public tokenValueMultiplier;

  /// Stop trigger in excess
  bool public stopped;

  /// @dev Constructor
  /// @param _token SNTR token address
  /// @param _ethMultisigWallet wallet address to transfer invested ETH
  /// @param _tokenMultisigWallet wallet address to withdraw unused tokens
  /// @param _startTime ICO start time
  /// @param _duration ICO duration in seconds
  /// @param _prolongedDuration Prolonged ICO duration in seconds, 0 if no prolongation is planned
  /// @param _tokenPrice Token price in wei
  /// @param _minInvestment Minimal investment amount in wei
  /// @param _allowedSenders List of addresses allowed to send ETH to this contract, empty if anyone is allowed
  function SilentNotaryTokenSale(address _token, address _ethMultisigWallet, address _tokenMultisigWallet,
            uint _startTime, uint _duration, uint _prolongedDuration, uint _tokenPrice, uint _minInvestment, address[] _allowedSenders) public {
    require(_token != 0);
    require(_ethMultisigWallet != 0);
    require(_tokenMultisigWallet != 0);
    require(_duration > 0);
    require(_tokenPrice > 0);
    require(_minInvestment > 0);

    token = ERC20(_token);
    ethMultisigWallet = _ethMultisigWallet;
    tokenMultisigWallet = _tokenMultisigWallet;
    startTime = _startTime;
    duration = _duration;
    prolongedDuration = _prolongedDuration;
    tokenPrice = _tokenPrice;
    minInvestment = _minInvestment;
    allowedSenders = _allowedSenders;
    tokenValueMultiplier = 10 ** token.decimals();
  }

  /// @dev Sell tokens to specified address
  /// @param receiver receiver of bought tokens
  function buy (address receiver) public payable {
    require(!stopped);
    require(getCurrentStatus() == Status.Selling || getCurrentStatus() == Status.ProlongedSelling);
    require(msg.value >= minInvestment);

    // Check if current sender is allowed to participate in this crowdsale
    var senderAllowed = false;
    if (allowedSenders.length > 0) {
      for (uint i = 0; i < allowedSenders.length; i++)
        if (allowedSenders[i] == receiver) {
          senderAllowed = true;
          break;
        }
    }
    else
      senderAllowed = true;

    assert(senderAllowed);

    uint weiAmount = msg.value;
    uint tokenAmount = safeDiv(safeMul(weiAmount, tokenValueMultiplier), tokenPrice);
    assert(tokenAmount > 0);

    uint changeWei = 0;
    var currentContractTokens = token.balanceOf(address(this));
    if (currentContractTokens < tokenAmount) {
      var changeTokenAmount = safeSub(tokenAmount, currentContractTokens);
      changeWei = safeDiv(safeMul(changeTokenAmount, tokenPrice), tokenValueMultiplier);
      tokenAmount = currentContractTokens;
      weiAmount = safeSub(weiAmount, changeWei);
    }

    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }
    // Update investor-amount mappings
    investedAmountOf[receiver] = safeAdd(investedAmountOf[receiver], weiAmount);
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver], tokenAmount);
    // Update totals
    weiRaisedAmount = safeAdd(weiRaisedAmount, weiAmount);
    tokensSoldAmount = safeAdd(tokensSoldAmount, tokenAmount);

    // Transfer the invested ETH to the multisig wallet;
    ethMultisigWallet.transfer(weiAmount);

    // Transfer the bought tokens to the ETH sender
    var transferSuccess = token.transfer(receiver, tokenAmount);
    assert(transferSuccess);

    // Return change if any
    if (changeWei > 0) {
      receiver.transfer(changeWei);
    }

    // Tell us the investment succeeded
    Invested(receiver, weiAmount, tokenAmount);
  }

  /// @dev Sell tokens to ETH sender
  function() public payable {
    buy(msg.sender);
  }

   /// @dev Token sale state machine management.
   /// @return Status current status
  function getCurrentStatus() public constant returns (Status) {
    if (startTime > now)
      return Status.Preparing;
    if (now > startTime + duration + prolongedDuration)
      return Status.Finished;
    if (now > startTime + duration && !prolongationPermitted)
      return Status.Finished;
    if (token.balanceOf(address(this)) <= 0)
      return Status.TokenShortage;
    if (now > startTime + duration)
      return Status.ProlongedSelling;
    if (now >= startTime)
        return Status.Selling;
    return Status.Unknown;
  }

  /// @dev Withdraw remaining tokens to the team wallet
  /// @param value Amount of tokens to withdraw
  function withdrawTokens(uint value) public onlyOwner {
    require(value <= token.balanceOf(address(this)));
    // Return the specified amount of tokens to team wallet
    token.transfer(tokenMultisigWallet, value);
    Withdraw(value);
  }

  /// @dev Change current token price
  /// @param newTokenPrice New token unit price in wei
  function changeTokenPrice(uint newTokenPrice) public onlyOwner {
    require(newTokenPrice > 0);

    tokenPrice = newTokenPrice;
    TokenPriceChanged(newTokenPrice);
  }

  /// @dev Prolong ICO if owner decides to do it
  function prolong() public onlyOwner {
    require(!prolongationPermitted && prolongedDuration > 0);
    prolongationPermitted = true;
  }

  /// @dev Called by the owner on excess, triggers stopped state
  function stopSale() public onlyOwner {
    stopped = true;
  }

  /// @dev Called by the owner on end of excess, returns to normal state
  function resumeSale() public onlyOwner {
    require(stopped);
    stopped = false;
  }

  /// @dev Called by the owner to destroy contract
  function kill() public onlyOwner {
    selfdestruct(owner);
  }
}
