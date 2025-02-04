import fs from "fs";

// Define the API endpoint and request options
const url = "https://hub.kaito.ai/api/v1/gateway/ai?duration=7d&topic_id=&top_n=100";

const options = {
    method: "POST",
    headers: {
        "accept": "application/json, text/plain, */*",
        "content-type": "application/json",
    },
    body: JSON.stringify({
        path: "/api/yapper/public_kol_mindshare_leaderboard",
        method: "GET",
        params: {
            duration: "7d",
            topicid: "",
            topn: 100,
        },
        body: {},
    }),
};

// Capture start time
const startTime = Date.now();

// Make the API call
fetch(url, options)
    .then((response) => {
        if (!response.ok) {
            throw new Error(`HTTP error! Status: ${response.status}`);
        }
        return response.json();
    })
    .then((data) => {
        // Capture end time and compute latency
        const endTime = Date.now();
        const latency = (endTime - startTime) / 1000; // Convert ms to seconds

        console.log(`API Response Latency: ${latency.toFixed(3)} seconds`);
        // console.log("API Response:", data);

        // Save the response to a JSON file
        const filePath = "api_response.json"; // File path to save the response
        fs.writeFile(filePath, JSON.stringify(data, null, 2), (err) => {
            if (err) {
                console.error("Error writing to file:", err);
            } else {
                console.log(`API response saved to ${filePath}`);
            }
        });
    })
    .catch((error) => {
        console.error("Error fetching data:", error);
    });
