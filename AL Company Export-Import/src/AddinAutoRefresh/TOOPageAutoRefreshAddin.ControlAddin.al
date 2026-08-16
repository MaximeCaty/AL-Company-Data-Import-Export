controladdin TOOPageAutoRefreshAddin
{
    MaximumHeight = 1;
    MaximumWidth = 1;
    MinimumHeight = 0;
    MinimumWidth = 0;
    RequestedHeight = 0;
    RequestedWidth = 0;
    // The Scripts property can reference both external and local scripts.
    Scripts = 'src/AddinAutoRefresh/PageAutoRefreshAddin-Addin.js';
    StartupScript = 'src/AddinAutoRefresh/PageAutoRefreshAddin-Startup.js';

    // The procedure declarations specify what JavaScript methods could be called from AL.
    procedure GetExtensionParam()

    procedure Run(MillisecondsInterval: Integer)

    // The event declarations specify what callbacks could be raised from JavaScript by using the webclient API:
    // Microsoft.Dynamics.NAV.InvokeExtensibilityMethod('CallBack', [42, 'some text', 5.8, 'c'])
    event AddinReady();

    event Refresh();
}