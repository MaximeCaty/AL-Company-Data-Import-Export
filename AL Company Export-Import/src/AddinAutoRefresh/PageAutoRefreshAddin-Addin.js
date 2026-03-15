async function Run(MillisecondsInterval)
{
    await sleep(MillisecondsInterval);
    Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('Refresh', [], false);
}

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}