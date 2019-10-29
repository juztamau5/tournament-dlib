/// @title RevealInstantiator
/// @author Felipe Argento
pragma solidity ^0.5.0;

import ".//Decorated.sol";
import ".//VGInterface.sol";
import "./RevealInterface.sol";
import "../arbitration-dlib/contracts/Merkle.sol";

contract RevealInstantiator is RevealInterface, Decorated {

    struct RevealCtx {
        uint256 instantiatedAt;
        uint256 commitDuration;
        uint256 revealDuration;
        uint256 scoreWordPosition;
        uint256 logDrivePosition;
        uint256 scoreDriveLogSize;
        uint256 logDriveLogSize;

        bytes32 setupHash;
        mapping(address => Player) players; //player address to player

        state currentState;
    }

    struct Player {
        address playerAddr;
        bool hasRevealed;
        uint256 score;
        bytes32 initialHash;
        bytes32 finalHash;
        bytes32 logHash;
    }


    event logCommited(uint256 index, address player, bytes32 logHash);
    event logRevealed(uint256 index, address player, bytes32 logHash);

    mapping(uint256 => RevealCtx) internal instance;

    constructor() public {
    }

    /// @notice Instantiate a commit and reveal instance.
    /// @param _commitDuration commit phase duration in seconds.
    /// @param _revealDuration reveal phase duration in seconds.
    /// @param _setupHash hash of the machine as is
    /// @param _scoreWordPosition position of the drive containing the score
    /// @param _logDrivePosition position of the drive containing the log
    /// @param _scoreDriveLogSize log2 of the score drive's size
    /// @param _logDriveLogSize log2 of the log drive's size
    /// @return Reveal index.
    function instantiate(
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _scoreWordPosition,
        uint256 _logDrivePosition,
        uint256 _scoreDriveLogSize,
        uint256 _logDriveLogSize,
        bytes32 _setupHash) public returns (uint256)
    {
        RevealCtx storage currentInstance = instance[currentIndex];
        currentInstance.instantiatedAt = now;
        currentInstance.commitDuration = _commitDuration;
        currentInstance.revealDuration = _revealDuration;
        currentInstance.setupHash = _setupHash;

        currentInstance.scoreWordPosition = _scoreWordPosition;
        currentInstance.logDrivePosition = _logDrivePosition;
        currentInstance.scoreWordPosition = _scoreWordPosition;
        currentInstance.logDriveLogSize = _logDriveLogSize;

        currentInstance.currentState = state.CommitPhase;


        active[currentIndex] = true;
        return currentIndex++;
    }

    /// @notice Submits a commit.
    /// @param _index index of reveal that is being interacted with.
    /// @param _logHash hash of log to be revealed later.
    function commit(uint256 _index, bytes32 _logHash) public {
        require(instance[_index].currentState == state.CommitPhase, "State has to be commit phase");

        // if its first commit, creates player
        if (instance[_index].players[msg.sender].playerAddr == address(0)) {
            Player memory player;
            player.playerAddr = msg.sender;
            instance[_index].players[msg.sender] = player;
        }

        instance[_index].players[msg.sender].logHash = _logHash;

        emit logCommited(_index, msg.sender, _logHash);
    }

    /// @notice reveals the log and extracts its information.
    /// @param _index index of reveal that is being interacted with.
    /// @param _score that should be contained in the log
    /// @param _finalHash final hash of the machine after that log has been proccessed.
    /// @param _logDriveHash hash of the drive with the log
    /// @param _scoreDriveHash hash of the drive with the score
    /// @param _logDriveSiblings siblings for the log drive
    /// @param _scoreDriveSiblings siblings for the log drive
    function reveal(uint256 _index,
                    uint256 _score,
                    bytes32 _finalHash,
                    bytes32 _logDriveHash,
                    bytes32 _scoreDriveHash,
                    bytes32[] memory _logDriveSiblings,
                    bytes32[] memory _scoreDriveSiblings
    ) public {
        require(instance[_index].currentState != state.CommitRevealDone, "Commit and Reveal cannot be over");
        // if commit deadline is over, can reveal
        if (now > instance[_index].instantiatedAt + instance[_index].commitDuration) {
            instance[_index].currentState = state.RevealPhase;
        }

        require(instance[_index].currentState == state.RevealPhase, "State has to be reveal phase");
        require(!instance[_index].players[msg.sender].hasRevealed, "Player can only reveal one commit");

        // TO-DO: Integrate with logger
        // use logger to see if logHash is available

        // TO-DO: improve this - create uint64 type for dispatcher
        uint64[4] memory uint64_values;
        uint64_values[0] = uint64(instance[_index].logDrivePosition); // logDrivePos64
        uint64_values[1] = uint64(instance[_index].logDriveLogSize); // logDriveLog64

        uint64_values[2] = uint64(instance[_index].scoreWordPosition); // scoreDrivePos64
        uint64_values[3] = uint64(instance[_index].scoreDriveLogSize); // scoreDriveLog64

        // TO-DO: decide if the hash of the previous drive will be hardcoded or a parameter
        //require(Merkle.getRootWithDrive(uint64_values[0], uint64_values[1], instance[_index].emptyLogDriveHash, _logDriveSiblings) == instance[_index].setupHash, "Logs sibling must be compatible with pristine hash for an empty drive");

        // TO-DO: Require that scoreDriveHash == Keccak(score)? Maybe remove the scoreDriveHash variable completely.
        // require that score is contained in the final hash
        require(Merkle.getRootWithDrive(uint64_values[2], uint64_values[3], _scoreDriveHash, _scoreDriveSiblings) == _finalHash, "Score is not contained in the final hash");

        // Update pristine hash with flash drive containing logs
        instance[_index].players[msg.sender].initialHash = Merkle.getRootWithDrive(uint64_values[0], uint64_values[1], _logDriveHash, _logDriveSiblings);

        instance[_index].players[msg.sender].score = _score;
        instance[_index].players[msg.sender].finalHash = _finalHash;
        instance[_index].players[msg.sender].hasRevealed = true;

        emit logRevealed(_index, msg.sender, instance[_index].players[msg.sender].logHash);
    }

    /// @notice Change state for final, if the deadlines were met.
    /// @param _index index of reveal that is being interacted with.
    function endCommitAndReveal(uint256 _index) public {
        require(instance[_index].currentState != state.CommitRevealDone, "Commit and Reveal is already over");

        if (now > instance[_index].instantiatedAt + instance[_index].commitDuration + instance[_index].revealDuration) {
            instance[_index].currentState = state.CommitRevealDone;
        }
    }

    function getScore(uint256 _index, address _playerAddr) public returns (uint256) {
        require(playerExist(_index, _playerAddr), "Player has to exist");
        return instance[_index].players[msg.sender].score;
    }

    function getFinalHash(uint256 _index, address _playerAddr) public returns (bytes32) {
        require(playerExist(_index, _playerAddr), "Player has to exist");
        return instance[_index].players[_playerAddr].finalHash;
    }

    function getInitialHash(uint256 _index, address _playerAddr) public returns (bytes32) {
        require(playerExist(_index, _playerAddr), "Player has to exist");
        return instance[_index].players[_playerAddr].initialHash;
    }

    function playerExist(uint256 _index, address _playerAddr) public returns (bool) {
        //cheap way to check if player has been registered
        return instance[_index].players[_playerAddr].playerAddr != address(0);
    }

    function removePlayer(uint256 _index, address _playerAddr) public {
        instance[_index].players[_playerAddr].playerAddr = address(0);
    }

    function getState(uint256 _index, address _user)
    public view returns (
            uint256[6] memory _uintValues,
            bytes32 setupHash,
            bool hasRevealed,

            bytes32 currentState
        ) {

        RevealCtx memory i = instance[_index];
        uint256[6] memory uintValues = [
            i.instantiatedAt,
            i.commitDuration,
            i.revealDuration,
            i.scoreWordPosition,
            i.logDrivePosition,
            i.logDriveLogSize
        ];

        return (
            uintValues,
            i.setupHash,
            instance[_index].players[_user].hasRevealed,

            getCurrentState(_index)
        );
    }

    function getCurrentState(uint256 _index) public view
        onlyInstantiated(_index)
        returns (bytes32)
    {
        if (instance[_index].currentState == state.CommitPhase) {
            return "CommitPhase";
        }

        if (instance[_index].currentState == state.RevealPhase) {
            return "RevealPhase";
        }

        if (instance[_index].currentState == state.CommitRevealDone) {
            return "CommitRevealDone";
        }
    }

    function isConcerned(uint256 _index, address _user) public view returns (bool) {
        return instance[_index].players[_user].playerAddr != address(0);
    }
    function getSubInstances(uint256 _index, address _user)
        public view returns (address[] memory _addresses,
            uint256[] memory _indices)
    {
        address[] memory a = new address[](0);
        uint256[] memory i = new uint256[](0);

        return (a, i);
    }

}

