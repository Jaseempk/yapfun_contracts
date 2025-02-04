// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title YapOracle
 * @dev This contract is used to store and update KOL (Key Opinion Leader) data.
 * It uses the AccessControl module from OpenZeppelin to manage roles and permissions.
 */
contract YapOracle is AccessControl {
    //error

    error YO__InvalidParams();

    struct KOLData {
        uint256 rank;
        uint256 mindshareScore;
        uint256 timestamp;
        uint256 updateBlock;
    }

    // Heartbeat check
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    uint256 public constant MAX_UPDATE_DELAY = 1 hours;

    // kolId => KOLData
    mapping(uint256 => KOLData) public kolData;
    mapping(uint256 => uint256) public lastUpdateTime;

    event KOLDataUpdated(
        uint256 indexed kolId,
        uint256 rank,
        uint256 mindshareScore,
        uint256 timestamp
    );

    event StaleData(uint256 indexed kolId, uint256 lastUpdateTime);

    /**
     * @dev Constructor that sets the initial roles and grants the updater role to the specified address.
     * @param updater The address to which the updater role will be granted.
     */
    constructor(address updater) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, updater);
    }

    /**
     * @dev Function to update KOL data. Only the address with the updater role can call this function.
     * @param kolIds An array of KOL IDs.
     * @param ranks An array of ranks corresponding to the KOL IDs.
     * @param mindshareScores An array of mindshare scores corresponding to the KOL IDs.
     */
    function updateKOLData(
        uint256[] calldata kolIds,
        uint256[] calldata ranks,
        uint256[] calldata mindshareScores
    ) external onlyRole(UPDATER_ROLE) {
        if (
            kolIds.length != ranks.length ||
            ranks.length != mindshareScores.length
        ) revert YO__InvalidParams();

        for (uint256 i = 0; i < kolIds.length; i++) {
            uint256 kolId = kolIds[i];
            uint256 newRank = ranks[i];

            if (block.timestamp - lastUpdateTime[kolId] > MAX_UPDATE_DELAY) {
                emit StaleData(kolId, lastUpdateTime[kolId]);
            }

            // Validate data
            if (newRank == 0 || mindshareScores[i] == 0 || kolId == 0)
                revert YO__InvalidParams();

            kolData[kolId] = KOLData({
                rank: newRank,
                mindshareScore: mindshareScores[i],
                timestamp: block.timestamp,
                updateBlock: block.number
            });

            lastUpdateTime[kolId] = block.timestamp;

            emit KOLDataUpdated(
                kolId,
                newRank,
                mindshareScores[i],
                block.timestamp
            );
        }
    }

    /**
     * @dev Function to update the updater role. Only the admin can call this function.
     * @param _newUpdater The address to which the updater role will be granted.
     */
    function updateUpdater(
        address _newUpdater
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(UPDATER_ROLE, _newUpdater);
    }

    /**
     * @dev Function to revoke the updater role. Only the admin can call this function.
     * @param _currentUpdater The address from which the updater role will be revoked.
     */
    function revokeUpdaterRole(
        address _currentUpdater
    ) public onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(UPDATER_ROLE, _currentUpdater);
    }

    /**
     * @dev Function to get KOL data.
     * @param kolId The ID of the KOL.
     * @return rank The rank of the KOL.
     * @return mindshareScore The mindshare score of the KOL.
     * @return timestamp The timestamp of the last update.
     * @return isStale A boolean indicating whether the data is stale.
     */
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
