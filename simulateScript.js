import { simulateScript, Location, ReturnType, CodeLanguage, decodeResult } from "@chainlink/functions-toolkit";
import fs from "fs";

async function main() {
    const { responseBytesHexstring, capturedTerminalOutput, errorString } = await simulateScript({
        source: fs.readFileSync("./script.js").toString(),
        codeLocation: Location.Inline,
        secrets: { secretKey: process.env.SECRET_KEY ?? "" }, // you can use your api-key as secretKey if required
        secretsLocation: Location.DONHosted,
        args: [], // since in your case, there are no arguments
        codeLanguage: CodeLanguage.JavaScript,
        expectedReturnType: ReturnType.string,
    })

    // console.log("capturedTerminalOutput:", capturedTerminalOutput);
    // console.log("responseBytesHexstring:", responseBytesHexstring);

    if (errorString) {
        console.log("Error:", errorString);
    }
    else {
        console.log("Decoded Result: ", decodeResult(responseBytesHexstring, ReturnType.string));
    }
}

main();