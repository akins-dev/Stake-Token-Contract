FactoryContract : 0xf6990FF3424EC81d48122b1926d32932B043E9dd
Staking Contract: 0xec60c81123afe579bae26a0e6bee2b76b0ff455a // 1hour lockDuration
Teller Token: 0xF8A37509C8a1ee397e8585A4C84B02358a2240A8 
use this while testing:
Testnet BSC SetUp 
Name: Testnet BSC
symbol: tBNB
RPC: https://bsc-testnet-rpc.publicnode.com
ChainId: 97
forge test --mt testDeposit  --fork-url=https://rpc.therpc.io/bsc-testnet -vvvvvvv