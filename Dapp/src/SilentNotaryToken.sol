pragma solidity ^0.4.13;

import '/src/common/lifecycle/Killable.sol';
import '/src/common/token/ERC20.sol';
import '/src/common/SafeMath.sol';

/*
This code is in the testing stage and may contain certain bugs.
These bugs will be identified and eliminated by the team at the testing stage before the ICO.
Please treat with understanding. If you become aware of a problem, please let us know by e-mail: service@silentnotary.com.
If the problem is critical and security related, we will credit you with the reward from the team's share in the tokens
at the end of the ICO (as officially announced at bitcointalk.org).
Thanks for the help.
*/

 /// @title SilentNotaryToken contract - standard ERC20 token with Short Hand Attack and approve() race condition mitigation.
contract SilentNotaryToken is SafeMath, ERC20, Killable {
  string constant public name = "Silent Notary Token";
  string constant public symbol = "SNTR";
  uint constant public decimals = 4;

  /// Minimum amount for starting buyout logic in wei
  uint public minBuyOutAmount = 0;
  /// Buyout price
  uint constant public buyOutPrice = 200 finney;
  /// Holder list
  address[] holders;
  /// Balance data
  struct Balance {
    /// Tokens amount
    uint value;
    /// Object exist
    bool exist;
  }
  /// Holder balances
  mapping(address => Balance) balances;
  /// Contract that is allowed to create new tokens and allows unlift the transfer limits on this token
  address public crowdsaleAgent;
  /// A crowdsale contract can release us to the wild if ICO success. If false we are are in transfer lock up period.
  bool public released = false;
  /// approve() allowances
  mapping (address => mapping (address => uint)) allowed;

  /// @dev Limit token transfer until the crowdsale is over.
  modifier canTransfer() {
    if(!released)
      require(msg.sender == crowdsaleAgent);
    _;
  }

  /// @dev The function can be called only before or after the tokens have been releasesd
  /// @param _released token transfer and mint state
  modifier inReleaseState(bool _released) {
    require(_released == released);
    _;
  }

  /// @dev If holder does not exist add to array
  /// @param holder Token holder
  modifier addIfNotExist(address holder) {
    if(!balances[holder].exist)
      holders.push(holder);
    _;
  }

  /// @dev The function can be called only by release agent.
  modifier onlyCrowdsaleAgent() {
    require(msg.sender == crowdsaleAgent);
    _;
  }

  /// @dev Fix for the ERC20 short address attack http://vessenes.com/the-erc20-short-address-attack-explained/
  /// @param size payload size
  modifier onlyPayloadSize(uint size) {
    require(msg.data.length >= size + 4);
    _;
  }

  /// @dev Make sure we are not done yet.
  modifier canMint() {
    require(!released);
    _;
  }

  /// Tokens burn event
  event Burned(address indexed burner, address indexed holder, uint burnedAmount);
  /// Tokens buyout event
  event Pay(address indexed to, uint value);
  /// Wei deposit event
  event Deposit(address indexed from, uint value);

  /// @dev Constructor
  function SilentNotaryToken() {
    owner = msg.sender;
  }

  /// Fallback method will buyout tokens
  function() payable {
    require(msg.value > 0);
    buyout();
  }
  /// @dev Create new tokens and allocate them to an address. Only callably by a crowdsale contract
  /// @param receiver Address of receiver
  /// @param amount  Number of tokens to issue.
  function mint(address receiver, uint amount) onlyCrowdsaleAgent canMint addIfNotExist(receiver) public {
      totalSupply = safeAdd(totalSupply, amount);
      balances[receiver].value = safeAdd(balances[receiver].value, amount);
      balances[receiver].exist = true;
      Transfer(0, receiver, amount);
  }
  /// @dev Set minimum limit for starting buyout logic
  /// @param _minBuyOutAmount min buyout amount
  function setBuyoutMinAmount(uint _minBuyOutAmount) onlyOwner public {
    minBuyOutAmount = _minBuyOutAmount;
  }
  /// @dev Set the contract that can call release and make the token transferable.
  /// @param _crowdsaleAgent crowdsale contract address
  function setCrowdsaleAgent(address _crowdsaleAgent) onlyOwner inReleaseState(false) public {
    crowdsaleAgent = _crowdsaleAgent;
  }
  /// @dev One way function to release the tokens to the wild. Can be called only from the release agent that is the final ICO contract. It is only called if the crowdsale has been success (first milestone reached).
  function releaseTokenTransfer() public onlyCrowdsaleAgent {
    released = true;
  }
  /// @dev Tranfer tokens to address
  /// @param _to dest address
  /// @param _value tokens amount
  /// @return transfer result
  function transfer(address _to, uint _value) onlyPayloadSize(2 * 32) canTransfer addIfNotExist(_to) returns (bool success) {
    balances[msg.sender].value = safeSub(balances[msg.sender].value, _value);
    balances[_to].value = safeAdd(balances[_to].value, _value);
    balances[_to].exist = true;
    Transfer(msg.sender, _to, _value);
    return true;
  }

  /// @dev Tranfer tokens from one address to other
  /// @param _from source address
  /// @param _to dest address
  /// @param _value tokens amount
  /// @return transfer result
  function transferFrom(address _from, address _to, uint _value) onlyPayloadSize(2 * 32) canTransfer addIfNotExist(_to) returns (bool success) {
    var _allowance = allowed[_from][msg.sender];

    balances[_to].value = safeAdd(balances[_to].value, _value);
    balances[_from].value = safeSub(balances[_from].value, _value);
    balances[_to].exist = true;

    allowed[_from][msg.sender] = safeSub(_allowance, _value);
    Transfer(_from, _to, _value);
    return true;
  }
  /// @dev Tokens balance
  /// @param _owner holder address
  /// @return balance amount
  function balanceOf(address _owner) constant returns (uint balance) {
    return balances[_owner].value;
  }

  /// @dev Approve transfer
  /// @param _spender holder address
  /// @param _value tokens amount
  /// @return result
  function approve(address _spender, uint _value) returns (bool success) {
    // To change the approve amount you first have to reduce the addresses`
    //  allowance to zero by calling `approve(_spender, 0)` if it is not
    //  already 0 to mitigate the race condition described here:
    //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    require ((_value == 0) || (allowed[msg.sender][_spender] == 0));

    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  /// @dev Token allowance
  /// @param _owner holder address
  /// @param _spender spender address
  /// @return remain amount
  function allowance(address _owner, address _spender) constant returns (uint remaining) {
    return allowed[_owner][_spender];
  }

  /// @dev Internal burn
  /// @param _holder holder address
  /// @param _amount burn amount
  function burn(address _holder, uint _amount) internal  {
      address burner = msg.sender;
      balances[_holder].value = safeSub(balances[_holder].value, _amount);
      totalSupply = safeSub(totalSupply, _amount);
      Burned(burner, _holder, _amount);
      /// Keep exchanges happy by sending the burned amount to
      /// "burn address"
      Transfer(burner, 0x0, _amount);
  }

  /// @dev Internal buyout method
  function buyout() internal  {
    Deposit(msg.sender, msg.value);
    uint balance = safeAdd(this.balance, msg.value);

    /// if amount less than min limit will store ether in contract
    if(balance < minBuyOutAmount)
        return;

    uint multiplier = 10 ** decimals;
    uint totalSupplyInt = safeDiv(totalSupply, multiplier);

    for (uint i = 0; i < holders.length; i++) {
      var holder = holders[i];

      uint tokenPortion = safeDiv(balances[holder].value, totalSupplyInt);
      uint weiPortion = safeDiv(safeMul(tokenPortion, balance), multiplier);

      if(weiPortion > 0 && weiPortion >= buyOutPrice) {
        uint buyoutTokens = safeDiv(safeMul(weiPortion, multiplier), buyOutPrice);
        burn(holder, buyoutTokens);
        holder.transfer(weiPortion);
        Pay(holder, weiPortion);
      }
    }
  }
}
