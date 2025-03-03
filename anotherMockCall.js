const axios = require('axios');

async function makeApiCall() {
    try {
        const url = 'https://hub.kaito.ai/api/v1/gateway/ai?kol=1852674305517342720&type=kol&duration=30d&nft_filter=true&topic_id=';

        const headers = {
            'accept': 'application/json, text/plain, */*',
            'accept-language': 'en-US,en;q=0.9',
            'authorization': 'Bearer', // Replace with your actual Bearer token if needed
            'content-type': 'application/json',
            'origin': 'https://yaps.kaito.ai',
            'priority': 'u=1, i',
            'privy-id-token': '', // Add your actual token here if required
            'referer': 'https://yaps.kaito.ai/',
            'sec-ch-ua': '"Not(A:Brand";v="99", "Google Chrome";v="133", "Chromium";v="133"',
            'sec-ch-ua-mobile': '?1',
            'sec-ch-ua-platform': '"Android"',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-site',
            'user-agent': 'Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/133.0.0.0 Mobile Safari/537.36'
        };

        const data = {
            path: '/api/yapper/public_kol_mindshare',
            method: 'GET',
            params: {
                kol: '1852674305517342720',
                type: 'kol',
                duration: '30d',
                nft_filter: true,
                topic_id: ''
            },
            body: {}
        };

        const response = await axios.post(url, data, { headers });
        console.log('Response:', response.data);
    } catch (error) {
        console.error('Error making API call:', error.response ? error.response.data : error.message);
    }
}

makeApiCall();