const url = "https://hub.kaito.ai/api/v1/gateway/ai?duration=7d&topic_id=&top_n=100";

const request = Functions.makeHttpRequest({
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
    request,
]);

const responseStatus = response.status;
console.log(`\nResponse status: ${responseStatus}\n`);
console.log(response);
console.log(`\n`);

const { data } = response;

// Replace `paramName` with the exact parameter name available in the response JSON or you can also return some portion of the response JSON after converting that to string format using `JSON.stringify()`
return Functions.encodeString(data[0].user_id)  