// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract YapOracle is AccessControl {
    //error
    error YO__InvalidParams();
    error YO__InvalidRank();

    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");

    struct KOLData {
        uint256 rank;
        uint256 mindshareScore;
        uint256 timestamp;
        uint256 updateBlock;
    }

    // kolId => KOLData
    mapping(uint256 => KOLData) public kolData;

    // Heartbeat check
    uint256 public constant MAX_UPDATE_DELAY = 1 hours;
    mapping(uint256 => uint256) public lastUpdateTime;

    event KOLDataUpdated(
        uint256 indexed kolId,
        uint256 rank,
        uint256 mindshareScore,
        uint256 timestamp
    );

    event StaleData(uint256 indexed kolId, uint256 lastUpdateTime);

    constructor(address updater) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, updater);
    }

    modifier onlyUpdater() {
        require(hasRole(UPDATER_ROLE, msg.sender), "Not authorized");
        _;
    }

    function updateKOLData(
        uint256[] calldata kolIds,
        uint256[] calldata ranks,
        uint256[] calldata mindshareScores
    ) external onlyUpdater {
        if (
            kolIds.length != ranks.length ||
            ranks.length != mindshareScores.length
        ) revert YO__InvalidParams();

        uint256 timestamp = block.timestamp;

        for (uint256 i = 0; i < kolIds.length; i++) {
            uint256 kolId = kolIds[i];
            uint256 newRank = ranks[i];

            // Validate data
            if (newRank <= 0) revert YO__InvalidRank();
            require(mindshareScores[i] > 0, "Invalid mindshare");

            kolData[kolId] = KOLData({
                rank: newRank,
                mindshareScore: mindshareScores[i],
                timestamp: timestamp,
                updateBlock: block.number
            });

            lastUpdateTime[kolId] = timestamp;

            emit KOLDataUpdated(kolId, newRank, mindshareScores[i], timestamp);
        }
    }

    function getKOLData(
        uint256 kolId
    )
        external
        view
        returns (
            uint256 rank,
            uint256 mindshareScore,
            uint256 timestamp,
            bool isStale
        )
    {
        KOLData memory data = kolData[kolId];
        isStale = block.timestamp - lastUpdateTime[kolId] > MAX_UPDATE_DELAY;

        return (data.rank, data.mindshareScore, data.timestamp, isStale);
    }
}
