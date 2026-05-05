// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract WaveLite {
    address public maintainer;
    uint256 public totalPoints;
    uint256 public totalPool;
    bool public waveEnded;

    mapping(address => uint256) public contributorPoints;

    error OnlyMaintainer();
    error WaveAlreadyEnded();
    error WaveNotEnded();
    error NoPoints();
    error TransferFailed();

    event PointsAdded(address indexed contributor, uint256 points);
    event WaveClosed(uint256 totalPool, uint256 totalPoints);
    event Claimed(address indexed contributor, uint256 amount);

    constructor() payable {
        maintainer = msg.sender;
        totalPool = msg.value;
    }

    function addPoints(address contributor, uint256 points) external {
        if (msg.sender != maintainer) revert OnlyMaintainer();
        if (waveEnded) revert WaveAlreadyEnded();
        contributorPoints[contributor] += points;
        totalPoints += points;
        emit PointsAdded(contributor, points);
    }

    function endWave() external {
        if (msg.sender != maintainer) revert OnlyMaintainer();
        if (totalPoints == 0) revert NoPoints();
        totalPool = address(this).balance;
        waveEnded = true;
        emit WaveClosed(totalPool, totalPoints);
    }

    function claim() external {
        if (!waveEnded) revert WaveNotEnded();
        uint256 points = contributorPoints[msg.sender];
        if (points == 0) revert NoPoints();
        uint256 share = (points * totalPool) / totalPoints;
        contributorPoints[msg.sender] = 0;
        (bool ok, ) = payable(msg.sender).call{value: share}("");
        if (!ok) revert TransferFailed();
        emit Claimed(msg.sender, share);
    }
}
