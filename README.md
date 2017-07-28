# ICO-SilentNotary.
<p align="center">
<img src="https://github.com/SilentNotary/ICO-SN/blob/master/logo_SN_png_256%D1%85256.png" width="25%" alt="SilentNotary">
</p>

### Introduction.

Published documents are the code of contracts, which are required  to conduct ICO and demontrational work of the service. A more detailed description of the service can be found in WhitePaper.

### How It Works.

The scheme of the service is quite simple. Using various interfaces to interact with the user, there is created an archive, including the date, the details of the document and the witnessed document itself (it can be a file, a protocol of correspondence, etc.).  
<p align="center">
<img src="https://github.com/SilentNotary/ICO-SN/blob/master/Shema_4.png" width="75%" alt="SilentNotary">
</p>
Next, the hash of this archive is calculated  by the algorithm <a href="https://en.wikipedia.org/wiki/SHA-2" target="_blank">H-256</a> and, through the smart contract, written to the chain of Etherium blocks. The archive itself is saved in the storageThe user receives a Hash (the result of computing the hash function on the user's archive), TxHash (the hash of the transaction in the blockchain Etherium), and a link to the document in his personal account.

### The content of published documents.

SmartContract | Description
| ------------ | ------------- |
|  <a href="https://github.com/SilentNotary/ICO-SN/blob/master/dapp/src/SilentNotaryToken.sol" target="_blank">Token</a>| The SNTR token contract made according to the standard ERC20. Total number of tokens is 1x10^12SNTR. In the contract, there is the possibility of forcing the tokens from the holders at the rate 1лю SNTR=0.2ETH. In order to avoid a large number of small transactions, the exchange of SNTRs to ETH occurs when the specified volume of ETH is reached (the parameter will be set after the ICO taking into account the number of holders)|
|<a href="https://github.com/SilentNotary/ICO-SN/blob/master/dapp/src/SilentNotaryCrowdsale.sol" target="_blank">Crowdsale</a>|Crowdsale contract, the contract has the following feature: the exchange rate of ETH to SNTR depends on the volume of realized SNTRs, the initial exchange rate is 1M SNTR = 0.01ETH and the final exchange rate is 1M SNTR = 0.2ETH. The total duration of the ICO is not more than 14 days.|
| <a href="https://github.com/SilentNotary/ICO-SN/blob/master/dapp/src/MultiSigWallet.sol" target="_blank">MultiSign</a>| The contract managing wallet to collect ETH, has 4 signatures, two signatures of team members, two signatures of Escrow. The funds can be used during the signing by two team members and one of the Escrows.|
| <a href="https://github.com/SilentNotary/ICO-SN/blob/master/dapp/src/SilentNotary.sol" target="_blank">SilentNotary_demo</a>|This is the main service contract operating in the demonstration mode. The basic service contract targeting the exchange of tokens and / or charging users will be developed and published here after the ICO|

### Discalimer request.

Friends and colleagues, pay an attention to the fact that the published code is at the testing stage. We hope that, including your help, we will be able to eliminate possible defects or bugs that may arise. At this moment, we continue testing this code and, as necessary, will make changes and additions to it. The final version of the code should appear 24 hours before the ICO. We believe that with mutual efforts we will make the product satisfying our common needs. 



