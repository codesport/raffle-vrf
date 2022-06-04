// SPDX-License-Identifier: MIT

pragma solidity ^0.8.12;

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import "@chainlink/contracts/src/v0.8/interfaces/KeeperCompatibleInterface.sol";
import "hardhat/console.sol";


error Raffle__SendMoreMoneyToEnterRaffle();
error Raffle__RaffleNotOpen();
error Raffle__TransferFailed();
error Raffle__UpkeepNotNeeded(uint256 currentBalance, uint256 numPlayers, uint256 raffleState);

contract Raffle is VRFConsumerBaseV2, KeeperCompatibleInterface {

    event RaffleEnter( address indexed player);
    event RequestedRaffleWinner(uint256 indexed requestId);
    event WinnerPicked(address indexed player);

    //Define State Variables (Globals)  Here:

    /**
    * Immutable vars (global, state variables) may only be assigned values once and only via the constructor.
    * They can never be changed after deployment. They are read-only
    * Also cheaper gas
    *
    * Constants are probbaly deprecated and can't be declared inside contructors. They are cheaper than immutables
    * 
    */
    uint256 public immutable i_entranceFee;
    uint256 public immutable i_interval;
    
    //s_ = storage    
    address payable[] public s_players;
    uint256 public s_lastTimeStamp;
    address private s_recentWinner;
    
    //Keep track of Raffle state via an enum type. Can use Bool as well it's also cheaper
    enum RaffleState{
        OPEN,
        CALCULATING
    }
    RaffleState public s_raffleState;


    // Chainlink VRF Variables
    VRFCoordinatorV2Interface private immutable i_vrfCoordinator;
    uint64 private immutable i_subscriptionId;
    bytes32 private immutable i_gasLane;
    uint32 private immutable i_callbackGasLimit;
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;    

    //interface + address ~ contract
    constructor(uint256 _entranceFee, uint256 _interval, address vrfCoordinatorV2, uint64 subscriptionId, bytes32 gasLane/*key hash*/, uint32 callbackGasLimit) VRFConsumerBaseV2(vrfCoordinatorV2){

        i_entranceFee = _entranceFee;
        i_interval = _interval; //time in seconds between each lottery run
        s_lastTimeStamp = block.timestamp;
        s_raffleState = RaffleState.OPEN;
        
        i_vrfCoordinator = VRFCoordinatorV2Interface(vrfCoordinatorV2);
        i_gasLane = gasLane; //how much cas to spend to cal this random numbvber
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

    }

    function enterRaffle() external payable{
        //require(msg.value >= i_entranceFee, "Please increase the wager");

        //use custom errors to save on gas
        if (msg.value < i_entranceFee ) {
            revert Raffle__SendMoreMoneyToEnterRaffle(); 
        }

        //check state of application
        if (s_raffleState != RaffleState.OPEN) {
            revert Raffle__RaffleNotOpen();
        }

        s_players.push(payable(msg.sender));
        emit RaffleEnter(msg.sender);

    }

/**
* Chainlink Keepers ~ OpenZeppelin Defender ~ contract automation ~ make an emitted vent trigger a tx on the blockchain
*   - Monitors the events.  When event occurs it executes a function
*
* Chainlink keepers require 2 special functions. For our use case, we need to them to check
*   1. A condition to be true adfter a given time interval
*   2. The lottery to be open
*   3. The contract has ETH
*   4. Keepers has LINK token
*
 */

    //1. Select random winner automatically
    //2. VRF Number (real random number)

    function checkUpkeep( bytes memory /*checkData*/) public view returns(bool upkeepNeeded, bytes memory /*performData*/) {

        bool isOpen = RaffleState.OPEN == s_raffleState;
        bool timePassed = ( (block.timestamp - s_lastTimeStamp) >= i_interval );
        bool hasBalance = address(this).balance > 0;
        bool hasPlayers = s_players.length > 0;
        upkeepNeeded = (timePassed && isOpen && hasBalance && hasPlayers);

        return(upkeepNeeded, "0x0"); //we are not using performData so we put "0x0" = empty bytes data


    }
    
    function performUpkeep( bytes calldata /*performData*/) external override {
        (bool upkeepNeeded, ) = checkUpkeep("");
        // require(upkeepNeeded, "Upkeep not needed");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded(
                address(this).balance,
                s_players.length,
                uint256(s_raffleState)
            );
        }
        s_raffleState = RaffleState.CALCULATING;
        uint256 requestId = i_vrfCoordinator.requestRandomWords(
            i_gasLane,
            i_subscriptionId,
            REQUEST_CONFIRMATIONS,
            i_callbackGasLimit,
            NUM_WORDS
        );
        // Quiz... is this redundant?
        emit RequestedRaffleWinner(requestId);
    }

    /**
     * @dev This is the function that Chainlink VRF node
     * calls to send the money to the random winner.
     */
    function fulfillRandomWords(
        uint256, /* requestId */
        uint256[] memory randomWords
    ) internal override {
        // s_players size 10
        // randomNumber 202
        // 202 % 10 ? what's doesn't divide evenly into 202?
        // 20 * 10 = 200
        // 2
        // 202 % 10 = 2
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable recentWinner = s_players[indexOfWinner];
        s_recentWinner = recentWinner;
        s_players = new address payable[](0);
        s_raffleState = RaffleState.OPEN;
        s_lastTimeStamp = block.timestamp;
        (bool success, ) = recentWinner.call{value: address(this).balance}("");
        // require(success, "Transfer failed");
        if (!success) {
            revert Raffle__TransferFailed();
        }
        emit WinnerPicked(recentWinner);
    }


/** Getter Functions */

    function getRaffleState() public view returns (RaffleState) {
        return s_raffleState;
    }

    function getNumWords() public pure returns (uint256) {
        return NUM_WORDS;
    }

    function getRequestConfirmations() public pure returns (uint256) {
        return REQUEST_CONFIRMATIONS;
    }

    function getRecentWinner() public view returns (address) {
        return s_recentWinner;
    }

    function getPlayer(uint256 index) public view returns (address) {
        return s_players[index];
    }

    function getLastTimeStamp() public view returns (uint256) {
        return s_lastTimeStamp;
    }

    function getInterval() public view returns (uint256) {
        return i_interval;
    }

    function getEntranceFee() public view returns (uint256) {
        return i_entranceFee;
    }

    function getNumberOfPlayers() public view returns (uint256) {
        return s_players.length;
    }    

}