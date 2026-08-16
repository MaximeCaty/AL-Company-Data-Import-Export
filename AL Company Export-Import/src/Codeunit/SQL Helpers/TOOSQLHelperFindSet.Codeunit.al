#if ONPREM
codeunit 51011 "TOO SQL Helper"
{
    EventSubscriberInstance = Manual;
    SingleInstance = true;

    var
        Self: Codeunit "TOO SQL Helper";


#region internal
    local procedure GetServerInstanceName(): Text
    var
        ActiveSession: Record "Active Session";
    begin
        ActiveSession.SetRange("Session ID", SessionId());
        ActiveSession.FindFirst();
        exit(ActiveSession."Server Instance Name");
    end;

    procedure GetSqlConnectionString(ForUpdate: Boolean): Text
    var
        XMLBuffer: Record "XML Buffer" temporary;
        ConfigFilePath, InstanceConfigPath, RootConfigPath : Text;
        DatabaseInstance: Text;
        DatabaseName: Text;
        DatabaseServer: Text;
        DataSource: Text;
        SQLConnectionString: TextBuilder;
    begin
        // BC Instance config
        InstanceConfigPath := ApplicationPath() + 'Instances\' + GetServerInstanceName() + '\CustomSettings.config';
        RootConfigPath := ApplicationPath() + 'CustomSettings.config';

        // Check config file exists
        if File.Exists(InstanceConfigPath) then
            ConfigFilePath := InstanceConfigPath
        else if File.Exists(RootConfigPath) then
            ConfigFilePath := RootConfigPath
        else
            Error('Server instance configuration not found. Unable to determine SQL connection string.');

        // Parse XML
        BindSubscription(Self); // skip attribute text value 250 overflow errors
        XMLBuffer.Load(ConfigFilePath);
        UnbindSubscription(Self);

        // Loop configuration properties
        DatabaseServer := GetConfigValue(XMLBuffer, 'DatabaseServer');
        DatabaseInstance := GetConfigValue(XMLBuffer, 'DatabaseInstance');
        DatabaseName := GetConfigValue(XMLBuffer, 'DatabaseName');

        // Data source
        if DatabaseInstance = '' then
            DataSource := DatabaseServer
        else
            DataSource := DatabaseServer + '\' + DatabaseInstance;

        // Build connection string
        SQLConnectionString.Append('Data Source=' + DataSource + ';');
        SQLConnectionString.Append('Initial Catalog=' + DatabaseName + ';');
        SQLConnectionString.Append('Integrated Security=True;');
        SQLConnectionString.Append('TrustServerCertificate=True;');
        SQLConnectionString.Append('Connection Timeout=10;');
        exit(SQLConnectionString.ToText());
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"XML Buffer Writer", 'OnBeforeCanPassValue', '', false, false)]
    local procedure XMLBufferSkipLongValues(Name: Text; Value: Text; var ReturnValue: Boolean; var IsHandled: Boolean)
    var
        XMLBuffer: Record "XML Buffer";
    begin
        if StrLen(Value) > MaxStrLen(XMLBuffer.Value) then begin
            ReturnValue := false;
            IsHandled := true;
        end;
    end;

    local procedure GetConfigValue(var XMLBuffer: Record "XML Buffer" temporary; KeyName: Text): Text
    begin
        /*
        I.E:
        <?xml version="1.0" encoding="utf-8"?>
        <appSettings>
            <add key="NetworkProtocol" value="Default" />
        */
        XMLBuffer.Reset();
        XMLBuffer.SetRange(Type, XMLBuffer.Type::Attribute);
        XMLBuffer.SetRange(Name, 'key');
        XMLBuffer.SetRange(Value, KeyName);
        if XMLBuffer.FindSet() then begin
            XMLBuffer.SetRange(Value);
            XMLBuffer.SetRange("Parent Entry No.", XMLBuffer."Parent Entry No.");
            XMLBuffer.SetRange(Name, 'value');
            if XMLBuffer.FindSet() then
                exit(XMLBuffer.Value);
        end;
        exit('');
    end;
#endregion
}
#endif