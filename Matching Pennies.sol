// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

contract MatchingPennies{
    
    //-------Data Structure-------------
    // the status of each player
    enum playerRole {FIRST, SECOND, CANDIDATE, NOTIN}
    // the status of each round
    enum roundStatus {FIRSTPCIK, SECONDPICK, FIRSTREVEAL, SECONDREVEAL, CHECK}
    // options of each pick, before revealing commitment, pick is set to UNREVEAL defaultly
    enum pickOptions {TRUE, FALSE, UNREVEAL}
    
    //each player's pick
    struct pickCommitment {
        address player;
        bytes32 commitment;
        pickOptions pick;
    }
    
    //--------Global Data----------------
    //record each player's balance in the contract
    mapping(address => uint256) public ledger;
    //record commitments for two in-game players
    pickCommitment[2] commitmentBox;
    
    //record the current round status
    roundStatus public curRoundStatus = roundStatus.FIRSTPCIK; 
    //mutex lock to prevent reentrancy
    bool lock = false;
    
    uint startTimestamp;
    uint startTimestamp2;
    uint decisionTime = 10;
    uint decisionTime2 = 20;
    
    //---------Public Functions-----------
    //Make deposit for anyone who intend to play
    function makeDeposit() public payable {
        require(!lock, "Reentrancy attack!");
        lock = true;
        require(msg.value > 1 ether && msg.value < 100 ether && 
            address(this).balance <= 1000 ether);
        
        ledger[msg.sender] += msg.value;
        lock = false;
    }
    
    //Everyone can check their status in the game
    function checkRole() public view returns (playerRole) {
        if (ledger[msg.sender] == 0){
            return playerRole.NOTIN;
        }
        else if (commitmentBox[0].player == msg.sender) {
            return playerRole.FIRST;
        }
        else if (commitmentBox[1].player == msg.sender) {
            return playerRole.SECOND;
        }
        else {
            return playerRole.CANDIDATE;
        }
    }
    
    //As long as users aren't in the middle of playing, they can withdraw their balance
    function withdrawDeposit() public payable {
        require(!lock, "Reentrancy attack");
        lock = true;
        playerRole _role = checkRole();
        
        require(_role != playerRole.NOTIN, "Have not made any deposit!");
        require(_role != playerRole.FIRST && 
            _role != playerRole.SECOND, "Finish game first!");
        
        uint256 _deposit = ledger[msg.sender];
        ledger[msg.sender] = 0;
        payable(msg.sender).transfer(_deposit);
        lock = false;
        
    }
    
    //Anyone who has make a deposit can join the game by making pick commitment
    function makePickCommitment(bytes32 commitment) public {
        require(ledger[msg.sender] > 1, "Not enough deposit!");
        require(curRoundStatus == roundStatus.FIRSTPCIK || 
            curRoundStatus == roundStatus.SECONDPICK, 
            "Two players are in the round, not time to pick.");
        
        uint _commitmentIndex;
        if (curRoundStatus == roundStatus.FIRSTPCIK) {
            _commitmentIndex = 0;
        }
        else {
            require(commitmentBox[0].player != msg.sender,
                "Cannot make a commitment for second time."); 
            require(commitmentBox[0].commitment != commitment, 
                "Cannot make two same commitments!");
            _commitmentIndex = 1;
        }
    
        commitmentBox[_commitmentIndex] = pickCommitment(msg.sender, commitment, pickOptions.UNREVEAL);
    
        if (curRoundStatus == roundStatus.FIRSTPCIK) {
            curRoundStatus = roundStatus.SECONDPICK;
        }
        else {
            startTimestamp2 = block.number;
            require(startTimestamp2 + decisionTime2 >= startTimestamp2, "Overflow Error!");
            curRoundStatus = roundStatus.FIRSTREVEAL;
        }
    }
    
    // Reveal the commitment
    function revealPick(pickOptions _option, uint _randNum) public {  
        require(curRoundStatus == roundStatus.FIRSTREVEAL || 
            curRoundStatus == roundStatus.SECONDREVEAL, 
            "Not time for revealing!");
        require(_option == pickOptions.TRUE ||
            _option == pickOptions.FALSE, 
            "Invalid Input");
        
        playerRole _role = checkRole();
        require(_role == playerRole.FIRST ||
            _role == playerRole.SECOND, 
            "Not in game!");
    
        require(keccak256(abi.encodePacked(msg.sender, _option, _randNum)) == commitmentBox[uint256(_role)].commitment, 
            "Unmatch between commitment and pick!");
        
        commitmentBox[uint256(_role)].pick = _option;
    
        if(curRoundStatus == roundStatus.FIRSTREVEAL) {
            // Set time limit for the other one to reveal
            startTimestamp = block.number;
            require(startTimestamp + decisionTime >= startTimestamp, "Overflow Error!");
            curRoundStatus = roundStatus.SECONDREVEAL;
        }
        else {
            curRoundStatus = roundStatus.CHECK;
        }
    }
    
    //Compare two picks and adjust the ledger accordingly
    function checkResult() public {
        require(curRoundStatus == roundStatus.CHECK || 
            (curRoundStatus == roundStatus.SECONDREVEAL && block.number >= startTimestamp + decisionTime) ||
            (curRoundStatus == roundStatus.FIRSTREVEAL && block.number >= startTimestamp2 + decisionTime2), 
            "Not time for checking!");
        
        if (commitmentBox[0].pick != pickOptions.UNREVEAL 
        			|| commitmentBox[1].pick != pickOptions.UNREVEAL) {
            address _winner;
            address _loser;
            if (commitmentBox[0].pick == commitmentBox[1].pick 
            	|| commitmentBox[1].pick == pickOptions.UNREVEAL){
                _winner = commitmentBox[0].player;
                _loser = commitmentBox[1].player;
            }
            else {
                _winner = commitmentBox[1].player;
                _loser = commitmentBox[0].player;
            }
            ledger[_winner] += 1 ether;
            ledger[_loser] -= 1 ether;            
        }
    
        curRoundStatus = roundStatus.FIRSTPCIK;
        startTimestamp = 0;
        delete commitmentBox;
    }

}