pragma solidity ^0.4.18;

import 'common/ownership/Ownable.sol';
import 'common/SafeMath.sol';
import 'common/token/ERC20.sol';

contract SilentNotaryTokenStorage is SafeMath, Ownable {

  /// Information about frozen portion of tokens
  struct FrozenPortion {
    /// Earliest time when this portion will become available
    uint unfreezeTime;

    /// Frozen balance portion, in percents
    uint portionPercent;

    /// Frozen token amount
    uint portionAmount;

    /// Is this portion unfrozen (withdrawn) after freeze period has finished
    bool isUnfrozen;
  }

  /// Specified amount of tokens was unfrozen
  event Unfrozen(uint tokenAmount);

  /// SilentNotary token contract
  ERC20 public token;

  /// All frozen portions of the contract token balance
  FrozenPortion[] public frozenPortions;

  /// Team wallet to withdraw unfrozen tokens
  address public teamWallet;

  /// Deployment time of this contract, which is also the start point to count freeze periods
  uint public deployedTime;

  /// Is current token amount fixed (must be to unfreeze)
  bool public amountFixed;

  /// @dev Constructor
  /// @param _token SilentNotary token contract address
  /// @param _teamWallet Wallet address to withdraw unfrozen tokens
  /// @param _freezePeriods Ordered array of freeze periods
  /// @param _freezePortions Ordered array of balance portions to freeze, in percents
  function SilentNotaryTokenStorage (address _token, address _teamWallet, uint[] _freezePeriods, uint[] _freezePortions) public {
    require(_token > 0);
    require(_teamWallet > 0);
    require(_freezePeriods.length > 0);
    require(_freezePeriods.length == _freezePortions.length);

    token = ERC20(_token);
    teamWallet = _teamWallet;
    deployedTime = now;

    var cumulativeTime = deployedTime;
    uint cumulativePercent = 0;
    for (uint i = 0; i < _freezePeriods.length; i++) {
      require(_freezePortions[i] > 0 && _freezePortions[i] <= 100);
      cumulativePercent = safeAdd(cumulativePercent, _freezePortions[i]);
      cumulativeTime = safeAdd(cumulativeTime, _freezePeriods[i]);
      frozenPortions.push(FrozenPortion({
        portionPercent: _freezePortions[i],
        unfreezeTime: cumulativeTime,
        portionAmount: 0,
        isUnfrozen: false}));
    }
    assert(cumulativePercent == 100);
  }

  /// @dev Unfreeze currently available amount of tokens
  function unfreeze() public onlyOwner {
    require(amountFixed);

    uint unfrozenTokens = 0;
    for (uint i = 0; i < frozenPortions.length; i++) {
      var portion = frozenPortions[i];
      if (portion.isUnfrozen)
        continue;
      if (portion.unfreezeTime < now) {
        unfrozenTokens = safeAdd(unfrozenTokens, portion.portionAmount);
        portion.isUnfrozen = true;
      }
      else
        break;
    }
    transferTokens(unfrozenTokens);
  }

  /// @dev Fix current token amount (calculate absolute values of every portion)
  function fixAmount() public onlyOwner {
    require(!amountFixed);
    amountFixed = true;

    uint currentBalance = token.balanceOf(this);
    for (uint i = 0; i < frozenPortions.length; i++) {
      var portion = frozenPortions[i];
      portion.portionAmount = safeDiv(safeMul(currentBalance, portion.portionPercent), 100);
    }
  }

  /// @dev Withdraw remaining tokens after all freeze periods are over (in case there were additional token transfers)
  function withdrawRemainder() public onlyOwner {
    for (uint i = 0; i < frozenPortions.length; i++) {
      if (!frozenPortions[i].isUnfrozen)
        revert();
    }
    transferTokens(token.balanceOf(this));
  }

  function transferTokens(uint tokenAmount) private {
    require(tokenAmount > 0);
    var transferSuccess = token.transfer(teamWallet, tokenAmount);
    assert(transferSuccess);
    Unfrozen(tokenAmount);
  }
}
