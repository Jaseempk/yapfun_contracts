import Functions from '@chainlink/functions-toolkit';

// const { Functions } = require('@chainlink/functions-toolkit');

async function fetchData() {
    const url = "https://hub.kaito.ai/api/v1/gateway/ai";

    const kaitoRequest = Functions.makeHttpRequest({
        method: 'POST',
        url: url,
        headers: {
            'accept': 'application/json, text/plain, */*',
            'content-type': 'application/json',
        },
        data: {
            path: "/api/yapper/public_kol_mindshare_leaderboard",
            method: "GET",
            params: {
                duration: "7d",
                topic_id: "",
                top_n: 100,
            },
            body: {},
        }
    });

    const [response] = await Promise.all([
        kaitoRequest,
    ]);

    const responseStatus = response.status;
    console.log(`\nResponse status: ${responseStatus}\n`);
    console.log(response);
    console.log(`\n`);

    const { data } = response;
    return data; // Return the full response data for further processing
}
fetchData();
