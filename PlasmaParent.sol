pragma solidity ^0.4.20;

import {RLP} from "./RLP.sol";
import {Conversion} from "./Conversion.sol";
import {ByteSlice} from "./ByteSlice.sol";
import {PriorityQueue} from "./PriorityQueue.sol";

contract PlasmaParent {
    using ByteSlice for bytes;
    using ByteSlice for ByteSlice.Slice;
    using Conversion for uint256;
    using RLP for RLP.RLPItem;
    using RLP for RLP.Iterator;
    using RLP for bytes;
    
    bool public plasmaErrorFound = false;
    uint256 public lastValidBlock = 0;
    PriorityQueue public exitQueue;
    
    address public owner = msg.sender;
    mapping(address => bool) public operators;
    uint32 public blockHeaderLength = 137;
    
    uint256 public lastBlockNumber = 0;
    uint256 public weekOldBlockNumber = 0;
    bytes32 public hashOfLastSubmittedBlock = keccak256("BankexFoundation");
    uint256 public lastEthBlockNumber = block.number;
    uint256 public depositCounterInBlock = 0;
    
    uint256 public DepositWithdrawCollateral = 0;
    uint256 public WithdrawCollateral = 0;
    uint256 public constant DepositWithdrawDelay = (72 hours);
    uint256 public constant WithdrawDelay = (168 hours);
    uint256 public constant ExitDelay = (336 hours);
    
    struct BlockInformation {
        uint256 submittedAt;
        bytes32 merkleRootHash;
    }

    struct TransactionInput {
        uint32 blockNumber;
        uint32 txNumberInBlock;
        uint8 outputNumberInTX;
        uint256 amount;
    }

    struct TransactionOutput {
        address recipient;
        uint8 outputNumberInTX;
        uint256 amount;
    }

    struct PlasmaTransaction {
        uint32 txNumberInBlock;
        uint8 txType;
        TransactionInput[] inputs;
        TransactionOutput[] outputs;
        address sender;
    }

    uint256 constant TxTypeNull = 0;
    uint256 constant TxTypeSplit = 1;
    uint256 constant TxTypeMerge = 2;
    uint256 constant TxTypeFund = 4;

    uint256 constant SignatureLength = 65;
    uint256 constant BlockNumberLength = 4;
    uint256 constant TxNumberLength = 4;
    uint256 constant TxTypeLength = 1;
    uint256 constant TxOutputNumberLength = 1;
    uint256 constant PreviousHashLength = 32;
    uint256 constant MerkleRootHashLength = 32;
    bytes constant PersonalMessagePrefixBytes = "\x19Ethereum Signed Message:\n";
    uint256 constant PreviousBlockPersonalHashLength = BlockNumberLength + 
                                                    TxNumberLength + 
                                                    PreviousHashLength + 
                                                    MerkleRootHashLength + 
                                                    SignatureLength;
    uint256 constant NewBlockPersonalHashLength = BlockNumberLength + 
                                                    TxNumberLength + 
                                                    PreviousHashLength + 
                                                    MerkleRootHashLength;

    mapping (uint256 => BlockInformation) public blocks;
    mapping (uint256 => uint256) public spentTransactions;
    
    event Debug(bool indexed _success, bytes32 indexed _b, address indexed _signer);
    event DebugUint(uint256 indexed _1, uint256 indexed _2, uint256 indexed _3);
    event SigEvent(address indexed _signer, bytes32 indexed _r, bytes32 indexed _s);

    function PlasmaParent() public {
        operators[msg.sender] = true;
        exitQueue = new PriorityQueue();
    }
    
    function incrementWeekOldCounter() internal {
        while (blocks[weekOldBlockNumber].submittedAt < now - (1 weeks)) {
            if (blocks[weekOldBlockNumber].submittedAt == 0) 
                break;
            weekOldBlockNumber++;
        }
    }
    
    function setOperator(address _op, bool _status) public returns (bool success) {
        require(msg.sender == owner);
        operators[_op] = _status;
        return true;
    }

    function submitBlockHeader(bytes _headers) public returns (bool success) {
        require(_headers.length % blockHeaderLength == 0);
        incrementWeekOldCounter();
        ByteSlice.Slice memory slice = _headers.slice();
        ByteSlice.Slice memory reusableSlice;
        uint256[] memory reusableSpace = new uint256[](5);
        bytes32 lastBlockHash = hashOfLastSubmittedBlock;
        for (uint256 i = 0; i < _headers.length/blockHeaderLength; i++) {
            reusableSlice = slice.slice(i*blockHeaderLength, (i+1)*blockHeaderLength);
            reusableSpace[0] = 0;
            reusableSpace[1] = BlockNumberLength;
            reusableSpace[2] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint(); //blockNumber
            require(reusableSpace[2] == lastBlockNumber+1);
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += TxNumberLength;
            reusableSpace[3] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint(); //numberOfTransactions
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 previousBlockHash = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            require(previousBlockHash == hashOfLastSubmittedBlock);
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 merkleRootHash = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 1;
            reusableSpace[4] = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toUint();
            if (reusableSpace[4] < 27) {
                reusableSpace[4] = reusableSpace[4]+27; 
            }
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 r = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            reusableSpace[0] = reusableSpace[1];
            reusableSpace[1] += 32;
            bytes32 s = reusableSlice.slice(reusableSpace[0],reusableSpace[1]).toBytes32();
            bytes32 newBlockHash = keccak256(PersonalMessagePrefixBytes, NewBlockPersonalHashLength.uintToBytes(), uint32(reusableSpace[2]), uint32(reusableSpace[3]), previousBlockHash, merkleRootHash);
            address signer = ecrecover(newBlockHash, uint8(reusableSpace[4]), r, s);
            SigEvent(signer, r, newBlockHash);
            // require(operators[signer]);
            lastBlockHash = newBlockHash;
            BlockInformation storage newBlockInformation = blocks[reusableSpace[2]];
            newBlockInformation.merkleRootHash = merkleRootHash;
            newBlockInformation.submittedAt = now;
            
        }
        hashOfLastSubmittedBlock = lastBlockHash;
        lastBlockNumber = reusableSpace[2];
        return true;
    }
    

// ----------------------------------
// Deposit related functions

    uint8 constant DepositStatusNoRecord = 0;
    uint8 constant DepositStatusDeposited = 1;
    uint8 constant DepositStatusWithdrawStarted = 2;
    uint8 constant DepositStatusWithdrawCompleted = 3;
    uint8 constant DepositStatusDepositConfirmed = 4;
    

    struct DepositRecord {
        address from; 
        uint8 status;
        bool hasCollateral;
        uint256 amount; 
        uint256 withdrawStartedAt;
    } 

    event DepositEvent(address indexed _from, uint256 indexed _amount, uint256 indexed _depositIndex);
    event DepositWithdrawStartedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawChallengedEvent(uint256 indexed _depositIndex);
    event DepositWithdrawCompletedEvent(uint256 indexed _depositIndex);
    
    mapping(uint256 => DepositRecord) public depositRecords;
    
    // function () payable external {
    //     deposit();
    // }


    function deposit() payable public returns (uint256 idx) {
        require(!plasmaErrorFound);
        if (block.number != lastEthBlockNumber) {
            depositCounterInBlock = 0;
        }
        uint256 depositIndex = block.number << 32 + depositCounterInBlock;
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusNoRecord);
        record.from = msg.sender;
        record.amount = msg.value;
        record.status = DepositStatusDeposited;
        depositCounterInBlock = depositCounterInBlock + 1;
        DepositEvent(msg.sender, msg.value, depositIndex);
        return depositIndex;
    }

    function startDepositWithdraw(uint256 depositIndex) public payable returns (bool success) {
        require(msg.value == DepositWithdrawCollateral || plasmaErrorFound);
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusDeposited);
        require(record.from == msg.sender);
        record.status = DepositStatusWithdrawStarted;
        record.withdrawStartedAt = now;
        record.hasCollateral = !plasmaErrorFound;
        DepositWithdrawStartedEvent(depositIndex);
        return true;
    }

    function finalizeDepositWithdraw(uint256 depositIndex) public returns (bool success) {
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusWithdrawStarted);
        require(now >= record.withdrawStartedAt + (72 hours));
        record.status = DepositStatusWithdrawCompleted;
        DepositWithdrawCompletedEvent(depositIndex);
        uint256 toSend = record.amount;
        if (record.hasCollateral) {
            toSend += DepositWithdrawCollateral;
        }
        record.from.transfer(toSend);
        return true;
    }

    function challengeDepositWithdraw(uint256 depositIndex,
                            uint32 _plasmaBlockNumber, 
                            bytes _plasmaTransaction, 
                            bytes _merkleProof) public returns (bool success) {
        DepositRecord storage record = depositRecords[depositIndex];
        require(record.status == DepositStatusWithdrawStarted);
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund);
        require(operators[TX.sender]);
        TransactionOutput memory output = TX.outputs[0];
        TransactionInput memory input = TX.inputs[0];
        require(output.recipient == record.from);
        require(output.amount == record.amount);
        require(input.amount == depositIndex);
        record.status = DepositStatusDepositConfirmed;
        DepositWithdrawChallengedEvent(depositIndex);
        if (record.hasCollateral) {
            msg.sender.transfer(DepositWithdrawCollateral);
        }
        return true;
    }
    
// ----------------------------------
// Withdrawrelated functions

    uint8 constant WithdrawStatusNoRecord = 0;
    uint8 constant WithdrawStatusStarted = 1;
    uint8 constant WithdrawStatusChallenged = 2;
    uint8 constant WithdrawStatusCompleted = 3;
    uint8 constant WithdrawStatusRejected = 4;
    
    enum WithdrawStatus {
        NoRecord,
        Started,
        Challenged,
        Completed,
        Rejected
    }

    struct WithdrawRecord {
        uint32 blockNumber;
        uint32 txNumberInBlock;
        uint8 outputNumberInTX;
        uint8 status;
        bool isExpress;
        bool hasCollateral;
        address beneficiary;
        uint256 amount;
        uint256 timestamp;
    }

    event WithdrawStartedEvent(uint32 indexed _blockNumber,
                                uint32 indexed _txNumberInBlock,
                                uint8 indexed _outputNumberInTX);
    event WithdrawRequestAcceptedEvent(address indexed _from,
                                uint256 indexed _withdrawIndex);
    event WithdrawFinalizedEvent(uint32 indexed _blockNumber,
                                uint32 indexed _txNumberInBlock,
                                uint8 indexed _outputNumberInTX);  
    event ExitStartedEvent(address indexed _from,
                            uint256 indexed _priority);  

    mapping(uint256 => WithdrawRecord) public withdrawRecords;
    
    function startWithdraw(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
                            uint32 _plasmaTxNumInBlock, 
                            uint8 _outputNumber,
                            bytes _plasmaTransaction, 
                            bytes _merkleProof) 
    public payable returns(bool success, uint256 withdrawIndex) {
        require(msg.value == WithdrawCollateral);
        if (plasmaErrorFound) {
            return startExit(_plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber, _plasmaTransaction, _merkleProof);
        }
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund || TX.txType == TxTypeSplit || TX.txType == TxTypeMerge);
        require(TX.sender != address(0));
        TransactionOutput memory output = TX.outputs[_outputNumber];
        require(output.recipient == msg.sender);
        var (_, index) = populateWithdrawRecordFromOutput(output, _plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber, true);
        WithdrawRequestAcceptedEvent(output.recipient, index);
        WithdrawStartedEvent(_plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber);
        return (true, index);
    } 

    function startExit(uint32 _plasmaBlockNumber, //references and proves ownership on output of original transaction
                            uint32 _plasmaTxNumInBlock, 
                            uint8 _outputNumber,
                            bytes _plasmaTransaction, 
                            bytes _merkleProof) 
        internal returns(bool success, uint256 withdrawIndex) {
            incrementWeekOldCounter();
            require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
            PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
            require(TX.txType == TxTypeFund || TX.txType == TxTypeSplit || TX.txType == TxTypeMerge);
            require(TX.sender != address(0));
            TransactionOutput memory output = TX.outputs[_outputNumber];
            require(output.recipient == msg.sender);
            var (_, index) = populateWithdrawRecordFromOutput(output, _plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber, true);
            uint256 priorityModifier = uint256(_plasmaBlockNumber) << 192;
            if (_plasmaBlockNumber < weekOldBlockNumber) {
                priorityModifier = weekOldBlockNumber << 192;
            }
            uint256 priority = priorityModifier + (index % (1 << 128));
            exitQueue.insert(priority);
            WithdrawStartedEvent(_plasmaBlockNumber, _plasmaTxNumInBlock, _outputNumber);
            ExitStartedEvent(output.recipient, priority);
            return (true, priority);
    }
    
    // stop the withdraw by presenting a transaction in Plasma chain 
    function challengeWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock, 
                            uint8 _inputNumber,
                            bytes _plasmaTransaction, 
                            bytes _merkleProof,
                            uint256 _withdrawIndex //references withdraw
                            ) public returns (bool success) {
        uint256 txIndex = makeTransactionIndex(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber);
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        require(TX.sender == record.beneficiary);
        require(TX.inputs[_inputNumber].blockNumber == record.blockNumber);
        require(TX.inputs[_inputNumber].blockNumber == record.txNumberInBlock);
        require(TX.inputs[_inputNumber].blockNumber == record.outputNumberInTX);
        record.status = WithdrawStatusChallenged;
        spentTransactions[_withdrawIndex % (1 << 128)] = txIndex;
        if (record.hasCollateral) {
            msg.sender.transfer(WithdrawCollateral);
        }
        return true;
    }
    
    function finalizeWithdraw(uint256 withdrawIndex) public returns(bool success) {
        WithdrawRecord storage record = withdrawRecords[withdrawIndex];
        require(record.status == WithdrawStatusStarted);
        if (plasmaErrorFound && record.blockNumber > lastValidBlock) {
            if (record.hasCollateral){
                address to = record.beneficiary;
                delete withdrawRecords[withdrawIndex];
                to.transfer(WithdrawCollateral);
            } else {
                delete withdrawRecords[withdrawIndex];
            }
            return true;
        }
        require(now >= record.timestamp + WithdrawDelay);
        record.status = WithdrawStatusCompleted;
        record.timestamp = now;
        WithdrawFinalizedEvent(record.blockNumber, record.txNumberInBlock, record.outputNumberInTX);
        uint256 toSend = record.amount;
        if (record.hasCollateral) {
            toSend += WithdrawCollateral;
        }
        record.beneficiary.transfer(toSend);
        return true;
    } 
    
    
    function finalizeExits(uint256 _numOfExits) public returns (bool success)
    {
        uint256 exitTimestamp = now - ExitDelay;
        uint256 withdrawIndex = exitQueue.getMin() % (1 << 128);
        WithdrawRecord storage currentRecord = withdrawRecords[withdrawIndex];
        for (uint i = 0; i <= _numOfExits; i++) {
            if (blocks[uint256(currentRecord.blockNumber)].submittedAt < exitTimestamp) {
                require(currentRecord.status == WithdrawStatusStarted);
                currentRecord.status = WithdrawStatusCompleted;
                currentRecord.beneficiary.transfer(currentRecord.amount);
                exitQueue.delMin();
                if (exitQueue.currentSize() > 0) {
                    withdrawIndex = exitQueue.getMin() % (1 << 128);
                    currentRecord = withdrawRecords[withdrawIndex];
                } else {
                    break;
                }
            }
        }
        return true;
    }

    function populateWithdrawRecordFromOutput(TransactionOutput memory _output, uint32 _blockNumber, uint32 _txNumberInBlock, uint8 _outputNumberInTX, bool _setCollateral) internal returns (WithdrawRecord storage record, uint256 withdrawIndex) {
        withdrawIndex = makeTransactionIndex(_blockNumber, _txNumberInBlock, _outputNumberInTX);
        withdrawIndex = withdrawIndex + (block.number << 128);
        record = withdrawRecords[withdrawIndex];
        require(record.status == WithdrawStatusNoRecord);
        record.status = WithdrawStatusStarted;
        record.isExpress = false;
        record.hasCollateral = _setCollateral;
        record.beneficiary = _output.recipient;
        record.amount = _output.amount;
        record.timestamp = now;
        record.blockNumber = _blockNumber;
        record.txNumberInBlock = _txNumberInBlock;
        record.outputNumberInTX = _outputNumberInTX;
        return (record, withdrawIndex);
    }

// ----------------------------------
// Double-spend related functions

    event DoubleSpendProovedEvent(uint256 indexed _txIndex1, uint256 indexed _txIndex2);
    event SpendAndWithdrawProovedEvent(uint256 indexed _txIndex, uint256 indexed _withdrawIndex);

// two transactions spend the same output
    function proveDoubleSpend(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            uint32 _plasmaTxNumInBlock1, 
                            uint8 _inputNumber1,
                            bytes _plasmaTransaction1, 
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            uint32 _plasmaTxNumInBlock2, 
                            uint8 _inputNumber2,
                            bytes _plasmaTransaction2, 
                            bytes _merkleProof2) public returns (bool success) {
        require(!plasmaErrorFound);
        uint256 index1 = makeTransactionIndex(_plasmaBlockNumber1, _plasmaTxNumInBlock1, _inputNumber1);
        uint256 index2 = makeTransactionIndex(_plasmaBlockNumber2, _plasmaTxNumInBlock2, _inputNumber2);
        require(index1 != index2);
        require(checkActualDoubleSpendProof(_plasmaBlockNumber1,
                            _plasmaTxNumInBlock1, 
                            _inputNumber1,
                            _plasmaTransaction1, 
                            _merkleProof1,
                            _plasmaBlockNumber2, 
                            _plasmaTxNumInBlock2, 
                            _inputNumber2,
                            _plasmaTransaction2, 
                            _merkleProof2));
        plasmaErrorFound = true;
        if (_plasmaBlockNumber1 < _plasmaBlockNumber2) {
            lastValidBlock = uint256(_plasmaBlockNumber2);
        } else {
            lastValidBlock = uint256(_plasmaBlockNumber1);
        }
        return true;
    }

    function checkActualDoubleSpendProof (uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            uint32 _plasmaTxNumInBlock1, 
                            uint8 _inputNumber1,
                            bytes _plasmaTransaction1, 
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            uint32 _plasmaTxNumInBlock2, 
                            uint8 _inputNumber2,
                            bytes _plasmaTransaction2, 
                            bytes _merkleProof2) public view returns (bool success) {
        var (signer1, input1) = getTXinputDetailsFromProof(_plasmaBlockNumber1, _plasmaTxNumInBlock1, _inputNumber1, _plasmaTransaction1, _merkleProof1);
        var (signer2, input2) = getTXinputDetailsFromProof(_plasmaBlockNumber2, _plasmaTxNumInBlock2, _inputNumber2, _plasmaTransaction2, _merkleProof2);
        require(signer1 != address(0));
        require(signer2 != address(0));
        require(signer1 == signer2);
        require(input1.blockNumber == input2.blockNumber);
        require(input1.txNumberInBlock == input2.txNumberInBlock);
        require(input1.outputNumberInTX == input2.outputNumberInTX);
        return true;
    }

// transaction output is withdrawn (witthout express process) and spent in Plasma chain
    function proveSpendAndWithdraw(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock, 
                            uint8 _inputNumber,
                            bytes _plasmaTransaction, 
                            bytes _merkleProof,
                            uint256 _withdrawIndex //references withdraw
                            ) public returns (bool success) {
        require(!plasmaErrorFound);
        uint256 txIndex = makeTransactionIndex(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber);
        WithdrawRecord storage record = withdrawRecords[_withdrawIndex];
        record.status == WithdrawStatusCompleted;
        var (signer, input) = getTXinputDetailsFromProof(_plasmaBlockNumber, _plasmaTxNumInBlock, _inputNumber, _plasmaTransaction, _merkleProof);
        require(signer != address(0));
        require(input.blockNumber == record.blockNumber);
        require(input.txNumberInBlock == record.txNumberInBlock);
        require(input.outputNumberInTX == record.outputNumberInTX);
        SpendAndWithdrawProovedEvent(txIndex, _withdrawIndex);
        plasmaErrorFound = true;
        lastValidBlock = uint256(_plasmaBlockNumber);
        return true;
    }
 
// ----------------------------------
// Prove unlawful funding transactions on Plasma

    event FundingWithoutDepositEvent(uint256 indexed _txIndex, uint256 indexed _depositIndex);                 
    event DoubleFundingEvent(uint256 indexed _txIndex1, uint256 indexed _txIndex2);

function proveFundingWithoutDeposit(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock, 
                            bytes _plasmaTransaction, 
                            bytes _merkleProof) public returns (bool success) {
        require(!plasmaErrorFound);
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund);
        require(operators[TX.sender]);
        TransactionOutput memory output = TX.outputs[0];
        TransactionInput memory input = TX.inputs[0];
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        uint256 depositIndex = input.amount;
        uint256 transactionIndex = makeTransactionIndex(_plasmaBlockNumber, TX.txNumberInBlock, 0);
        DepositRecord storage record = depositRecords[depositIndex];
        if (record.status == DepositStatusNoRecord) {
            plasmaErrorFound = true;
            lastValidBlock = uint256(_plasmaBlockNumber);
            return true;
        } else if (record.amount != output.amount || record.from != output.recipient) {
            plasmaErrorFound = true;
            lastValidBlock = uint256(_plasmaBlockNumber);
            return true;
        }
        revert();
        return false;
    }

    //prove double funding of the same 

    function proveDoubleFunding(uint32 _plasmaBlockNumber1, //references and proves transaction number 1
                            uint32 _plasmaTxNumInBlock1, 
                            bytes _plasmaTransaction1, 
                            bytes _merkleProof1,
                            uint32 _plasmaBlockNumber2, //references and proves transaction number 2
                            uint32 _plasmaTxNumInBlock2, 
                            bytes _plasmaTransaction2, 
                            bytes _merkleProof2) public returns (bool success) {
        require(!plasmaErrorFound);
        var (signer1, depositIndex1, transactionIndex1) = getFundingTXdetailsFromProof(_plasmaBlockNumber1, _plasmaTxNumInBlock1, _plasmaTransaction1, _merkleProof1);
        var (signer2, depositIndex2, transactionIndex2) = getFundingTXdetailsFromProof(_plasmaBlockNumber2, _plasmaTxNumInBlock2, _plasmaTransaction2, _merkleProof2);
        require(checkDoubleFundingFromInternal(signer1, depositIndex1, transactionIndex1, signer2, depositIndex2, transactionIndex2));
        plasmaErrorFound = true;
        if (_plasmaBlockNumber1 < _plasmaBlockNumber2) {
            lastValidBlock = uint256(_plasmaBlockNumber2);
        } else {
            lastValidBlock = uint256(_plasmaBlockNumber1);
        }
        return true;
    }

    function checkDoubleFundingFromInternal (address signer1,
                                            uint256 depositIndex1,
                                            uint256 transactionIndex1,
                                            address signer2,
                                            uint256 depositIndex2,
                                            uint256 transactionIndex2) public view returns (bool) {
        require(operators[signer1]);
        require(operators[signer2]);
        require(depositIndex1 == depositIndex2);
        require(transactionIndex1 != transactionIndex2);
        return true;
    }

// Prove invalid ownership in split or merge, or balance breaking inside a signle transaction or between transactions

// Balance breaking in TX
    function proveBalanceBreaking(uint32 _plasmaBlockNumber, //references and proves transaction
                            uint32 _plasmaTxNumInBlock, 
                            bytes _plasmaTransaction, 
                            bytes _merkleProof) public returns (bool success) {
        require(!plasmaErrorFound);
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        require(!isWellFormedTransaction(_plasmaTransaction));
        plasmaErrorFound = true;
        lastValidBlock = _plasmaBlockNumber;
        return true;
    }
    
// Prove that either amount of the input doesn't match the amount of the output, or spender of the output didn't have an ownership
    
    
// IMPORTANT Allow plasma operator to make merges on behalf of the users, in this case merge transaction MUST have 1 output that belongs to owner of original outputs
// Only operator have a power for such merges
    function proveBalanceOrOwnershipBreakingBetweenInputAndOutput(uint32 _plasmaBlockNumber, //references and proves ownership on withdraw transaction
                            uint32 _plasmaTxNumInBlock, 
                            bytes _plasmaTransaction, 
                            bytes _merkleProof,
                            uint32 _originatingPlasmaBlockNumber, //references and proves ownership on output of original transaction
                            uint32 _originatingPlasmaTxNumInBlock, 
                            bytes _originatingPlasmaTransaction, 
                            bytes _originatingMerkleProof,
                            uint256 _inputOfInterest
                            ) public returns(bool success) {
        require(!plasmaErrorFound);
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        require(checkForInclusionIntoBlock(_originatingPlasmaBlockNumber, _originatingPlasmaTransaction, _originatingMerkleProof));
        bool breaking = checkRightfullInputOwnershipAndBalance(_plasmaTransaction, _originatingPlasmaTransaction, _originatingPlasmaBlockNumber, _inputOfInterest);
        require(breaking);
        plasmaErrorFound = true;
        lastValidBlock = _plasmaBlockNumber;
        return true;
    } 
    
    function checkRightfullInputOwnershipAndBalance(bytes _spendingTXbytes, bytes _originatingTXbytes, uint32 _originatingPlasmaBlockNumber, uint256 _inputNumber) internal view returns (bool isValid) {
        PlasmaTransaction memory _spendingTX = plasmaTransactionFromBytes(_spendingTXbytes);
        PlasmaTransaction memory _originatingTX = plasmaTransactionFromBytes(_originatingTXbytes);
        require(_spendingTX.inputs[_inputNumber].blockNumber == _originatingPlasmaBlockNumber);
        require(_spendingTX.inputs[_inputNumber].txNumberInBlock == _originatingTX.txNumberInBlock);
        if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].amount != _spendingTX.inputs[0].amount) {
            return false;
        }
        if (_spendingTX.txType == TxTypeSplit) {
            if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].recipient != _spendingTX.sender) {
                return false;
            }
        } else if (_spendingTX.txType == TxTypeSplit) {
            if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].recipient != _spendingTX.sender) {
                if (!operators[_spendingTX.sender]) {
                    return false;
                }
                if (_spendingTX.outputs.length != 1) {
                    return false;
                }
                if (_originatingTX.outputs[uint256(_spendingTX.inputs[_inputNumber].outputNumberInTX)].recipient != _spendingTX.outputs[0].recipient) {
                    return false;
                }
            }
        }
        return true;
    }
    

// ----------------------------------
// Convenience functions

    function isWellFormedTransaction(bytes _plasmaTransaction) public view returns (bool isWellFormed) {
        PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
        if (TX.sender == address(0)) {
            return false;
        }
        uint256 balance = 0;
        uint8 counter = 0;
        if (TX.txType == TxTypeFund) {
            return true;
        } else if (TX.txType == TxTypeSplit || TX.txType == TxTypeMerge) {
            for (counter = 0; counter < TX.inputs.length; counter++) {
                balance += TX.inputs[counter].amount;
            }
            for (counter = 0; counter < TX.outputs.length; counter++) {
                balance += TX.outputs[counter].amount;
            }
            if (balance != 0) {
                return false;
            }
            return true;
        } 
        return false;
    }

   function getTXinputDetailsFromProof(uint32 _plasmaBlockNumber, 
                            uint32 _plasmaTxNumInBlock, 
                            uint8 _inputNumber,
                            bytes _plasmaTransaction, 
                            bytes _merkleProof) internal view returns (address signer, TransactionInput memory input) {
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType != TxTypeFund);
        require(TX.sender != address(0));
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        input = TX.inputs[uint256(_inputNumber)];
        return (TX.sender, input);
    }

    function getFundingTXdetailsFromProof(uint32 _plasmaBlockNumber, 
                            uint32 _plasmaTxNumInBlock, 
                            bytes _plasmaTransaction, 
                            bytes _merkleProof) internal view returns (address signer, uint256 depositIndex, uint256 transactionIndex) {
        require(checkForInclusionIntoBlock(_plasmaBlockNumber, _plasmaTransaction, _merkleProof));
        PlasmaTransaction memory TX = plasmaTransactionFromBytes(_plasmaTransaction);
        require(TX.txType == TxTypeFund);
        TransactionInput memory auxInput = TX.inputs[0];
        require(auxInput.blockNumber == 0);
        require(auxInput.txNumberInBlock == 0);
        require(auxInput.outputNumberInTX == 0);
        require(TX.txNumberInBlock == _plasmaTxNumInBlock);
        depositIndex = auxInput.amount;
        transactionIndex = makeTransactionIndex(_plasmaBlockNumber, TX.txNumberInBlock, 0);
        return (TX.sender, depositIndex, transactionIndex);
    }

    function plasmaTransactionFromBytes(bytes _rawTX) internal view returns (PlasmaTransaction memory TX) {
        RLP.Iterator memory iter = _rawTX.toRLPItem(true).iterator();
        RLP.RLPItem memory item = iter.next(true);
        uint32 numInBlock = uint32(item.toUint());
        item = iter.next(true);
        TX = signedPlasmaTransactionFromRLPItem(item);
        TX.txNumberInBlock = numInBlock;
        return TX;
    }
    
    function signedPlasmaTransactionFromRLPItem(RLP.RLPItem memory _item) internal view returns (PlasmaTransaction memory TX) {
        RLP.Iterator memory iter = _item.iterator();
        RLP.RLPItem memory item = iter.next(true);
        bytes memory rawSignedPart = item.toBytes();
        bytes32 persMessageHashWithoutNumber = createPersonalMessageTypeHash(rawSignedPart);
        TX = plasmaTransactionFromRLPItem(item);
        item = iter.next(true);
        uint8 v = uint8(item.toUint());
        item = iter.next(true);
        bytes32 r = item.toBytes32();
        item = iter.next(true);
        bytes32 s = item.toBytes32();
        TX.sender = ecrecover(persMessageHashWithoutNumber, v, r, s);
        return TX;
    }
    
    function plasmaTransactionFromRLPItem(RLP.RLPItem memory _item) internal pure returns (PlasmaTransaction memory TX) {
        RLP.Iterator memory iter = _item.iterator();
        RLP.RLPItem memory item = iter.next(true);
        uint256[] memory reusableSpace = new uint256[](7);
        reusableSpace[0] = item.toUint();
        item = iter.next(true);
        require(item.isList());
        RLP.Iterator memory reusableIterator = item.iterator();
        TransactionInput[] memory inputs = new TransactionInput[](item.items());
        reusableSpace[1] = 0;
        while (reusableIterator.hasNext()) {
            reusableSpace[2] = reusableIterator.next(true).toUint();
            reusableSpace[3] = reusableIterator.next(true).toUint();
            reusableSpace[4] = reusableIterator.next(true).toUint();
            reusableSpace[5] = reusableIterator.next(true).toUint();
            require(!reusableIterator.hasNext());
            TransactionInput memory input = TransactionInput({
                blockNumber: uint32(reusableSpace[2]),
                txNumberInBlock: uint32(reusableSpace[3]),
                outputNumberInTX: uint8(reusableSpace[4]),
                amount: reusableSpace[5]
            });
            inputs[reusableSpace[1]] = input;
            reusableSpace[1]++;
        }
        item = iter.next(true);
        require(item.isList());
        reusableIterator = item.iterator();
        TransactionOutput[] memory outputs = new TransactionOutput[](item.items());
        reusableSpace[1] = 0;
        while (reusableIterator.hasNext()) {
            reusableSpace[2] = reusableIterator.next(true).toUint();
            address recipient = reusableIterator.next(true).toAddress();
            reusableSpace[3] = reusableIterator.next(true).toUint();
            require(!reusableIterator.hasNext());
            TransactionOutput memory output = TransactionOutput({
                outputNumberInTX: uint8(reusableSpace[2]),
                recipient: recipient,
                amount: reusableSpace[3]
            });
            outputs[reusableSpace[1]] = output;
            reusableSpace[1]++;
        }
        TX = PlasmaTransaction({
            txNumberInBlock: 0,
            txType: uint8(reusableSpace[0]),
            inputs: inputs,
            outputs: outputs,
            sender: address(0)
        });
        return TX;
    }

    function createPersonalMessageTypeHash(bytes memory message) internal pure returns (bytes32 msgHash) {
        // bytes memory prefixBytes = "\x19Ethereum Signed Message:\n";
        bytes memory lengthBytes = message.length.uintToBytes();
        // bytes memory prefix = PersonalMessagePrefixBytes.concat(lengthBytes);
        return keccak256(PersonalMessagePrefixBytes, lengthBytes, message);
    }
    
    function checkForInclusionIntoBlock(uint32 _blockNumber, bytes _plasmaTransaction, bytes _merkleProof) internal view returns (bool included) {
        BlockInformation storage blockInformation = blocks[uint256(_blockNumber)];
        require(blockInformation.submittedAt > 0);
        included = checkProof(blockInformation.merkleRootHash, _plasmaTransaction, _merkleProof, true);
        return included;
    }

    function checkProof(bytes32 root, bytes data, bytes proof, bool convertToMessageHash) pure public returns (bool) {
        bytes32 h;
        if (convertToMessageHash) {
            h = createPersonalMessageTypeHash(data);
        } else {
            h = keccak256(data);
        }
        bytes32 elProvided;
        uint8 rightElementProvided;
        uint32 loc;
        uint32 elLoc;
        for (uint32 i = 32; i <= uint32(proof.length); i += 33) {
            assembly {
                loc  := proof 
                elLoc := add(loc, add(i, 1))
                elProvided := mload(elLoc)
            }
            rightElementProvided = uint8(bytes1(0xff)&proof[i-32]);
            if (rightElementProvided > 0) {
                h = keccak256(h, elProvided);
            } else {
                h = keccak256(elProvided, h);
            }
        }
        return h == root;
      }
    
    function makeTransactionIndex(uint32 _blockNumber, uint32 _txNumberInBlock, uint8 _outputNumberInTX) pure public returns (uint256 index) { 
        index = uint256(_blockNumber) << ((TxNumberLength + TxTypeLength)*8) + uint256(_txNumberInBlock) << (TxTypeLength*8) + uint256(_outputNumberInTX);
        return index;
    }
}
