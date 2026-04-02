#if ONPREM
codeunit 51011 "TOO SQL Helper FindSet"
{
    EventSubscriberInstance = Manual;

    var
        SQLFilter: Text;
        EmptyGuid: Guid;
        SQLSelect: Text;
        TableID: Integer;
        TableCompanyName: Text;
        Nofields: Integer;
        RequireExtJoin: Boolean;
        TableMeta: Record "Table Metadata";
        BaseTableSQLName: Text;
        ExtTableSQLName: Text;
        ListOfFieldInTableExt: List of [Integer];
        ListOfFieldInTableExtAppID: List of [Guid];
        ListSQLFieldsWithAlias: List of [Text];
        FieldTypes: array[500] of FieldType;


    #region internal
    local procedure GetTableExtJoinCondition(TableID: Integer; BaseAlias: Text; ExtAlias: Text) JoinCondition: Text
    var
        Field: Record "Field";
    begin
        // Feidls PK fields
        Field.SetRange(TableNo, TableID);
        Field.SetRange(IsPartOfPrimaryKey, true);
        Field.SetRange(ObsoleteState, Field.ObsoleteState::No);
        Field.SetRange(Enabled, true);
        Field.FindSet();
        repeat
            if JoinCondition <> '' then
                JoinCondition += ' AND ';
            JoinCondition += StrSubstNo('%1.[%2] = %3.[%2]', BaseAlias, EscapeSQLChar(Field."FieldName"), ExtAlias);
        until Field.Next() = 0;
    end;

    local procedure EscapeSQLChar(InputName: Text) OutPut: Text
    begin
        OutPut := InputName
                    .Replace('/', '_')
                    .Replace('\', '_')
                    .Replace('.', '_')
                    .Replace('''', '_')
                    .Replace('"', '_')
                    .Replace('[', '_')
                    .Replace(']', '_')
                    .Replace('%', '_')
    end;

    local procedure GetServerInstanceName(): Text
    var
        ActiveSession: Record "Active Session";
    begin
        ActiveSession.SetRange("Session ID", SessionId());
        ActiveSession.FindFirst();
        exit(ActiveSession."Server Instance Name");
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

    procedure GetSqlConnectionString(ForUpdate: Boolean): Text
    var
        InstanceConfigPath, RootConfigPath, ConfigFilePath : Text;
        DatabaseServer: Text;
        DatabaseInstance: Text;
        DatabaseName: Text;
        DataSource: Text;
        SQLConnectionString: TextBuilder;
        XMLBuffer: Record "XML Buffer" temporary;
        Self: Codeunit "TOO SQL Helper FindSet";
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

    procedure ConvertFilterToSQL(FilterText: Text; UseQuote: Boolean) Result: Text
    var
        AndParts: List of [Text];
        OrParts: List of [Text];
        i, j : Integer;
        AndPart, OrPart : Text;
        SQLOrParts: List of [Text];
        SQLAndParts: List of [Text];
        TempText: Text;
        RangeParts: List of [Text];
        Quote: Text;
    begin
        if UseQuote then
            Quote := '''';
        // Replce blank date placeholder
        FilterText := FilterText.Replace('0DT', '1753-01-01');
        FilterText := FilterText.Replace('0D', '1753-01-01');
        FilterText := FilterText.Replace('0T', '1753-01-01');

        // Step 1: Split by AND '&'
        AndParts := FilterText.Split('&');

        for i := 1 to AndParts.Count() do begin
            AndPart := AndParts.Get(i);

            // Step 2: Split by OR '|'
            OrParts := AndPart.Split('|');
            clear(SQLOrParts);

            for j := 1 to SQLOrParts.Count() do begin
                OrPart := OrParts.Get(j).Trim();

                // Step 3a: Handle range 'A..C'
                if StrPos(OrPart, '..') > 0 then begin
                    RangeParts := OrPart.Split('..');
                    if RangeParts.Count() = 2 then
                        SQLOrParts.Add('%1 BETWEEN ' + Quote + RangeParts.Get(1) + Quote + ' AND ' + Quote + RangeParts.Get(2) + Quote);
                end
                // Step 3b: Handle wildcard '*' -> '%' , '?' -> '_', '@' -> SQL pattern
                else if (StrPos(OrPart, '*') > 0) or (StrPos(OrPart, '?') > 0) or (StrPos(OrPart, '@') > 0) then begin
                    TempText := OrPart;
                    TempText := TempText.Replace('*', '%');
                    TempText := TempText.Replace('?', '_');
                    TempText := TempText.TrimStart('@').Replace('@', '%');
                    SQLOrParts.Add('%1 LIKE ''' + TempText + '''');
                end
                // Step 3c: Handle simple comparisons '<', '<=', '>', '>='
                else if Copystr(OrPart, 1, 2) = '<=' then
                    SQLOrParts.Add('%1 <= ' + Quote + Copystr(OrPart, 3) + Quote)
                else if Copystr(OrPart, 1, 2) = '>=' then
                    SQLOrParts.Add('%1 >= ' + Quote + Copystr(OrPart, 3) + Quote)
                else if Copystr(OrPart, 1, 1) = '<' then
                    SQLOrParts.Add('%1 < ' + Quote + Copystr(OrPart, 2) + Quote)
                else if Copystr(OrPart, 1, 1) = '>' then
                    SQLOrParts.Add('%1 > ' + Quote + Copystr(OrPart, 2) + Quote)
                // Step 3d: Otherwise, literal equality
                else
                    SQLOrParts.Add('%1 = ' + Quote + OrPart + Quote);
            end;

            // Step 4: Join OR parts
            if SQLOrParts.Count() = 1 then
                SQLAndParts.Add(SQLOrParts.Get(1))
            else
                SQLAndParts.Add('(' + ListJoin(' OR ', SQLOrParts) + ')');
        end;

        // Step 5: Join AND parts
        if SQLAndParts.Count() = 1 then
            Result := SQLAndParts.Get(1)
        else
            Result := '(' + ListJoin(' AND ', SQLAndParts) + ')';
    end;

    local procedure ListJoin(JoinWith: Text; List: List of [Text]) JoinTxt: Text
    var
        Val: Text;
    begin
        foreach Val in List do begin
            if JoinTxt <> '' then
                JoinTxt += JoinWith;
            JoinTxt += Val;
        end;
    end;
    #endregion
}
#endif