// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {FunctionsClient} from "lib/chainlink/contracts/src/v0.8/functions/dev/v1_X/FunctionsClient.sol";
import {FunctionsRequest} from "lib/chainlink/contracts/src/v0.8/functions/dev/v1_X/libraries/FunctionsRequest.sol";

contract YapOracle is AccessControl, FunctionsClient {
    using Strings for uint256;
    using FunctionsRequest for FunctionsRequest.Request;

    //error
    error YO__InvalidRank();
    error YO__InvalidParams();
    error YO__InvalidMindshareScore();
    error YO__ChainlinkFunctionsFailed(string);

    struct KOLData {
        uint256 rank;
        uint256 mindshareScore;
        uint256 timestamp;
        uint256 updateBlock;
    }

    uint8 private immutable i_slotId;
    uint64 private immutable i_secretVersion;
    string private i_kaioApiScript;
    bytes32 private immutable i_donId;
    uint64 private immutable i_subscriptionId;

    // Heartbeat check
    address public constant ROUTER__ADDRESS =
        0xf9B8fc078197181C841c296C876945aaa425B278;
    bytes32 public constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
    uint32 public constant CALLBACK_GAS_LIMIT = 300_000;
    uint256 public constant MAX_UPDATE_DELAY = 1 hours;

    // kolId => KOLData
    mapping(uint256 => KOLData) public kolData;
    mapping(uint256 => uint256) public lastUpdateTime;

    event KaitoDataRequestSent(address indexed sender, string script);
    event KOLDataRequestFulfilled(
        bytes response,
        bytes32 requestId,
        uint256 timestamp
    );
    event KOLDataUpdated(
        uint256 indexed kolId,
        uint256 rank,
        uint256 mindshareScore,
        uint256 timestamp
    );

    event StaleData(uint256 indexed kolId, uint256 lastUpdateTime);

    constructor(
        address updater,
        uint8 _slotId,
        uint64 secretVersion,
        string memory kaitoApiScript,
        bytes32 donId,
        uint64 subscriptionId
    ) FunctionsClient(ROUTER__ADDRESS) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(UPDATER_ROLE, updater);

        i_slotId = _slotId;
        i_secretVersion = secretVersion;
        i_kaioApiScript = kaitoApiScript;
        i_donId = donId;
        i_subscriptionId = subscriptionId;
    }

    function sendKaitoDataRequest()
        public
        onlyRole(UPDATER_ROLE)
        returns (bytes32)
    {
        // Prepare and send the Chainlink Functions request
        FunctionsRequest.Request memory req;
        req._initializeRequestForInlineJavaScript(i_kaioApiScript);
        req._addDONHostedSecrets(i_slotId, i_secretVersion);
        bytes32 requestId = _sendRequest(
            req._encodeCBOR(),
            i_subscriptionId,
            CALLBACK_GAS_LIMIT,
            i_donId
        );

        emit KaitoDataRequestSent(msg.sender, i_kaioApiScript);
        return requestId;
    }

    function _fulfillRequest(
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) internal override {
        if (err.length > 0) {
            // Handle the error
            revert YO__ChainlinkFunctionsFailed(string(err));
        }

        emit KOLDataRequestFulfilled(response, requestId, block.timestamp);
    }

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

            // Validate data
            if (newRank <= 0) revert YO__InvalidRank();
            if (mindshareScores[i] <= 0) revert YO__InvalidMindshareScore();


            kolData[kolId] = KOLData({
                rank: newRank,
                mindshareScore: mindshareScores[i],
                timestamp: block.timestamp,
                updateBlock: block.number
            });

            lastUpdateTime[kolId] = block.timestamp;

            emit KOLDataUpdated(kolId, newRank, mindshareScores[i], block.timestamp);
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
