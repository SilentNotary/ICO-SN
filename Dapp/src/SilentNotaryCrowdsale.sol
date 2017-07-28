pragma solidity ^0.4.13;

import '/src/common/SafeMath.sol';
import '/src/common/lifecycle/Haltable.sol';
import '/src/SilentNotaryToken.sol';
import '/src/common/lifecycle/Killable.sol';

/*
This code is in the testing stage and may contain certain bugs.
These bugs will be identified and eliminated by the team at the testing stage before the ICO.
Please treat with understanding. If you become aware of a problem, please let us know by e-mail: service@silentnotary.com.
If the problem is critical and security related, we will credit you with the reward from the team's share in the tokens
at the end of the ICO (as officially announced at bitcointalk.org).
Thanks for the help.
*/

 /// @title SilentNotary  сrowdsale contract
contract SilentNotaryCrowdsale is Haltable, Killable, SafeMath {

  /// The duration of ICO
  uint public constant ICO_DURATION = 14 days;

  //// The token we are selling
  SilentNotaryToken public token;

  /// Multisig wallet
  address public multisigWallet;

  /// The UNIX timestamp start date of the crowdsale
  uint public startsAt;

  /// the number of tokens already sold through this contract
  uint public tokensSold = 0;

  ///  How many wei of funding we have raised
  uint public weiRaised = 0;

  ///  How many distinct addresses have invested
  uint public investorCount = 0;

  ///  How much wei we have returned back to the contract after a failed crowdfund.
  uint public loadedRefund = 0;

  ///  How much wei we have given back to investors.
  uint public weiRefunded = 0;

  ///  Has this crowdsale been finalized
  bool public finalized;

  ///  How much ETH each address has invested to this crowdsale
  mapping (address => uint256) public investedAmountOf;

  ///  How much tokens this crowdsale has credited for each investor address
  mapping (address => uint256) public tokenAmountOf;

  /// if the funding goal is not reached, investors may withdraw their funds
  uint public constant FUNDING_GOAL = 20 ether;

  /// topup team wallet on 5(testing) Eth after that will topup both - team and multisig wallet by 32% and 68%
  uint constant MULTISIG_WALLET_GOAL = 5 ether;

  /// Minimum order quantity 0.1 ether
  uint public constant MIN_INVESTEMENT = 100 finney;

  /// ICO start token price
  uint public constant MIN_PRICE = 100 finney;

  /// Maximum token price, if reached ICO will stop
  uint public constant MAX_PRICE = 200 finney;

  /// How much ICO tokens to sold
  uint public constant INVESTOR_TOKENS  = 9e4;

  /// How much ICO tokens will get team
  uint public constant TEAM_TOKENS = 1e4;

  /// Tokens count involved in price calculation
  uint public constant TOTAL_TOKENS_FOR_PRICE = INVESTOR_TOKENS + TEAM_TOKENS;

  /// last token price
  uint public tokenPrice = MIN_PRICE;

   /// State machine
   /// Preparing: All contract initialization calls and variables have not been set yet
   /// Funding: Active crowdsale
   /// Success: Minimum funding goal reached
   /// Failure: Minimum funding goal not reached before ending time
   /// Finalized: The finalized has been called and succesfully executed
   /// Refunding: Refunds are loaded on the contract for reclaim
  enum State{Unknown, Preparing, Funding, Success, Failure, Finalized, Refunding}

  /// A new investment was made
  event Invested(address investor, uint weiAmount, uint tokenAmount);

  /// Refund was processed for a contributor
  event Refund(address investor, uint weiAmount);

  /// Crowdsale end time has been changed
  event EndsAtChanged(uint endsAt);

  /// New price was calculated
  event PriceChanged(uint oldValue, uint newValue);

  /// Modified allowing execution only if the crowdsale is currently runnin
  modifier inState(State state) {
    require(getState() == state);
    _;
  }

  /// @dev Constructor
  /// @param _token SNTR token address
  /// @param _multisigWallet  multisig wallet address
  /// @param _start  ICO start time
  function SilentNotaryCrowdsale(address _token, address _multisigWallet, uint _start) {
    require(_token != 0);
    require(_multisigWallet != 0);
    require(_start != 0);

    token = SilentNotaryToken(_token);
    multisigWallet = _multisigWallet;
    startsAt = _start;
  }

  /// @dev Don't expect to just send in money and get tokens.
  function() payable {
    buy();
  }

   /// @dev Make an investment.
   /// @param receiver The Ethereum address who receives the tokens
  function investInternal(address receiver) stopInEmergency private {
    require(getState() == State.Funding);
    require(msg.value >= MIN_INVESTEMENT);

    uint weiAmount = msg.value;

    var multiplier = 10 ** token.decimals();
    uint tokenAmount = safeDiv(safeMul(weiAmount, multiplier), tokenPrice);
    assert(tokenAmount > 0);

    if(investedAmountOf[receiver] == 0) {
       // A new investor
       investorCount++;
    }
    // Update investor
    investedAmountOf[receiver] = safeAdd(investedAmountOf[receiver], weiAmount);
    tokenAmountOf[receiver] = safeAdd(tokenAmountOf[receiver], tokenAmount);
    // Update totals
    weiRaised = safeAdd(weiRaised, weiAmount);
    tokensSold = safeAdd(tokensSold, tokenAmount);

    var newPrice = calculatePrice(tokensSold);
    PriceChanged(tokenPrice, newPrice);
    tokenPrice = newPrice;

    // Check that we did not bust the cap
    //if(isBreakingCap(weiAmount, tokenAmount, weiRaised, tokensSold)) {
    //  revert();
    //}

    assignTokens(receiver, tokenAmount);
    if(weiRaised <= MULTISIG_WALLET_GOAL)
      multisigWallet.transfer(weiAmount);
    else {
      int remain = int(weiAmount - weiRaised - MULTISIG_WALLET_GOAL);

      if(remain > 0) {
        multisigWallet.transfer(uint(remain));
        weiAmount = safeSub(weiAmount, uint(remain));
      }

      var distributedAmount = safeDiv(safeMul(weiAmount, 32), 100);
      owner.transfer(distributedAmount);
      multisigWallet.transfer(safeSub(weiAmount, distributedAmount));

    }
    // Tell us invest was success
    Invested(receiver, weiAmount, tokenAmount);
  }

   /// @dev Allow anonymous contributions to this crowdsale.
   /// @param receiver The Ethereum address who receives the tokens
  function invest(address receiver) public payable {
    investInternal(receiver);
  }

   /// @dev Pay for funding, get invested tokens back in the sender address.
  function buy() public payable {
    invest(msg.sender);
  }

  /// @dev Finalize a succcesful crowdsale. The owner can triggre a call the contract that provides post-crowdsale actions, like releasing the tokens.
  function finalize() public inState(State.Success) onlyOwner stopInEmergency {
    // If not already finalized
    require(!finalized);

    finalized = true;
    finalizeCrowdsale();
  }

  /// @dev Finalize a succcesful crowdsale.
  function finalizeCrowdsale() internal {
    var multiplier = 10 ** token.decimals();
    assignTokens(owner, safeMul(safeAdd(safeSub(INVESTOR_TOKENS, tokensSold), TEAM_TOKENS), multiplier));
    token.releaseTokenTransfer();
  }

   /// @dev  Allow load refunds back on the contract for the refunding. The team can transfer the funds back on the smart contract in the case the minimum goal was not reached.
  function loadRefund() public payable inState(State.Failure) {
    if(msg.value == 0)
      revert();
    loadedRefund = safeAdd(loadedRefund, msg.value);
  }

  /// @dev  Investors can claim refund.
  function refund() public inState(State.Refunding) {
    uint256 weiValue = investedAmountOf[msg.sender];
    if (weiValue == 0)
      revert();
    investedAmountOf[msg.sender] = 0;
    weiRefunded = safeAdd(weiRefunded, weiValue);
    Refund(msg.sender, weiValue);
    if (!msg.sender.send(weiValue))
      revert();
  }

   /// @dev Crowdfund state machine management.
   /// @return State current state
  function getState() public constant returns (State) {
    if (finalized)
      return State.Finalized;
    if (address(token) == 0 || address(multisigWallet) == 0)
      return State.Preparing;
    if (now >= startsAt && now < startsAt + ICO_DURATION && !isCrowdsaleFull())
      return State.Funding;
    if (isMinimumGoalReached())
        return State.Success;
    if (!isMinimumGoalReached() && weiRaised > 0 && loadedRefund >= weiRaised)
      return State.Refunding;
    return State.Failure;
  }

  /// @dev Calculating price, it is not linear function
  /// @param totalRaisedTokens total raised tokens
  /// @return price in wei
  function calculatePrice(uint totalRaisedTokens) internal returns (uint price) {
    int multiplier = int(10**token.decimals());
    int coefficient = int(safeDiv(totalRaisedTokens, TOTAL_TOKENS_FOR_PRICE)) - multiplier;
    int priceDifference = coefficient * int(MAX_PRICE - MIN_PRICE) / multiplier;
    assert(int(MAX_PRICE) >= -priceDifference);
    return uint(priceDifference + int(MAX_PRICE));
  }

   /// @dev Called from invest() to confirm if the curret investment does not break our cap rule.
   /// @param weiAmount tokens to buy
   /// @param tokenAmount tokens to buy
   /// @param weiRaisedTotal tokens to buy
   /// @param tokensSoldTotal tokens to buy
   /// @return limit result
   //function isBreakingCap(uint weiAmount, uint tokenAmount, uint weiRaisedTotal, uint tokensSoldTotal) constant returns (bool limitBroken) {
   //   return false;
   //}

   /// @dev Minimum goal was reached
   /// @return true if the crowdsale has raised enough money to be a succes
   function isMinimumGoalReached() public constant returns (bool reached) {
     return weiRaised >= FUNDING_GOAL;
   }

   /// @dev Check crowdsale limit
   /// @return limit reached result
   function isCrowdsaleFull() public constant returns (bool) {
     return tokenPrice >= MAX_PRICE
       || tokensSold >= safeMul(TOTAL_TOKENS_FOR_PRICE,  10 ** token.decimals())
       || now > startsAt + ICO_DURATION;
   }

    /// @dev Dynamically create tokens and assign them to the investor.
    /// @param receiver address
    /// @param tokenAmount tokens amount
   function assignTokens(address receiver, uint tokenAmount) private {
     token.mint(receiver, tokenAmount);
   }
}
