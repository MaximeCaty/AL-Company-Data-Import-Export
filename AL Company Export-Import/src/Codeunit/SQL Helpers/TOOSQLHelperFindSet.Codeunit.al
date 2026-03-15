codeunit 51011 "TOO SQL Helper FindSet"
{
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


    procedure Open(OpenTableID: Integer; FromCompanyName: Text)
    var
        SourceTableName: Text;
        Fields: Record Field;
        PublishedApp: Record "Published Application";
    begin
        TableMeta.Get(OpenTableID);
        SQLFilter := '';
        SQLSelect := '';
        TableID := OpenTableID;
        TableCompanyName := FromCompanyName;
        Nofields := 0;
        RequireExtJoin := false;
        clear(ListOfFieldInTableExt);
        clear(ListOfFieldInTableExtAppID);
        clear(ListSQLFieldsWithAlias);

        // Get SQL Table Name
        SourceTableName := EscapeSQLChar(TableMeta.Name);
        if TableMeta.DataPerCompany then
            if IsNullGuid(TableMeta."App ID") then
                BaseTableSQLName := StrSubstNo('%1$%2', TableCompanyName, SourceTableName)
            else
                BaseTableSQLName := StrSubstNo('%1$%2$%3', TableCompanyName, SourceTableName, DELCHR(TableMeta."App ID", '=', '{}'))
        else
            if IsNullGuid(TableMeta."App ID") then
                BaseTableSQLName := SourceTableName
            else
                BaseTableSQLName := StrSubstNo('%1$%2', SourceTableName, DELCHR(TableMeta."App ID", '=', '{}'));
        ExtTableSQLName := BaseTableSQLName + '$ext';

        // Get list of fields stored in extension table
        Fields.SetLoadFields("No.", "App Runtime Package ID");
        Fields.SetRange(TableNo, OpenTableID);
        Fields.SetRange(Class, Fields.Class::Normal);
        Fields.SetRange(ExternalName, '');
        Fields.SetFilter("App Runtime Package ID", '<>%1', EmptyGuid);
        if Fields.FindSet() then
            repeat
                // Check that the field is from different App ID than base table (tableextension in the same project are stored in base table)
                PublishedApp.SetLoadFields(ID);
                PublishedApp.SetFilter(ID, '<>%1', TableMeta."App ID");
                PublishedApp.SetRange("Runtime Package ID", Fields."App Runtime Package ID");
                PublishedApp.SetRange(Installed, true);
                if PublishedApp.FindFirst() then begin
                    ListOfFieldInTableExt.Add(Fields."No.");
                    ListOfFieldInTableExtAppID.Add(PublishedApp.ID);
                end;
            until Fields.Next() = 0;
    end;


    #region Filter
    procedure SetFilter(FieldRef: FieldRef; Filter: Text; Value1: Variant)
    begin
        SetFilter(FieldRef.Number, FieldRef.Name, FieldRef.Type, StrSubstNo(Filter, Value1));
    end;

    procedure SetFilter(FieldRef: FieldRef; Filter: Text)
    begin
        SetFilter(FieldRef.Number, FieldRef.Name, FieldRef.Type, Filter);
    end;

    procedure SetFilter(FieldID: Integer; FieldName: Text; FieldType: FieldType; Filter: Text; Value1: Variant)
    begin
        SetFilter(FieldID, FieldName, FieldType, StrSubstNo(Filter, Value1));
    end;

    procedure SetFilter(FieldID: Integer; FieldName: Text; FieldType: FieldType; Filter: Text)
    var
        FieldSQLName: Text;
        IndexOfFieldExt: Integer;
    begin
        if SQLFilter <> '' then
            SQLFilter += ' AND ';

        // Get Field SQL Name with extended App ID
        case FieldID of
            2000000001:
                FieldSQLName := '$systemCreatedAt';
            2000000002:
                FieldSQLName := '$systemCreatedBy';
            2000000003:
                FieldSQLName := '$systemModifiedAt';
            2000000004:
                FieldSQLName := '$systemModifiedBy';
            else
                FieldSQLName := EscapeSQLChar(FieldName);
        end;
        IndexOfFieldExt := ListOfFieldInTableExt.IndexOf(FieldID);
        if IndexOfFieldExt > 0 then
            FieldSQLName := 'ext.[' + FieldSQLName + '$' + DELCHR(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}') + '] ' // Field on ext table
        else
            FieldSQLName := 't.[' + FieldSQLName + '] '; // Field on original table

        // Convert AL filter to SQL
        if FieldType in [FieldType::Text, FieldType::Code, FieldType::Date, FieldType::DateTime, FieldType::Time, FieldType::DateFormula, FieldType::RecordId] then
            SQLFilter := StrSubstNo(ConvertFilterToSQL(Filter, true), FieldSQLName) // quote for text like values
        else
            SQLFilter := StrSubstNo(ConvertFilterToSQL(Filter, false), FieldSQLName); // no quote for numericals
    end;
    #endregion

    #region Load Field
    procedure AddLoadfields(var Fields: Record Field)
    var
        FieldsType: FieldType;
    begin
        case Fields.Type of
            /*
            OptionMembers = TableFilter,RecordID,OemText,Date,Time,DateFormula,Decimal,Media,MediaSet,Text,Code,Binary,BLOB,Boolean,Integer,OemCode,Option,BigInteger,Duration,GUID,DateTime;
            // This list must stay in sync with NCLOptionMetadataNavTypeField
            OptionOrdinalValues = 4912, 4988, 11519, 11775, 11776, 11797, 12799, 26207, 26208, 31488, 31489, 33791, 33793, 34047, 34559, 35071, 35583, 36095, 36863, 37119, 37375;
            */
            4912:
                FieldsType := FieldsType::TableFilter;
            4988:
                FieldsType := FieldsType::RecordID;
            11519:
                FieldsType := FieldsType::Text; //OemText
            11775:
                FieldsType := FieldsType::Date;
            11776:
                FieldsType := FieldsType::Time;
            11797:
                FieldsType := FieldsType::DateFormula;
            12799:
                FieldsType := FieldsType::Decimal;
            26207:
                FieldsType := FieldsType::Media;
            26208:
                FieldsType := FieldsType::MediaSet;
            31488:
                FieldsType := FieldsType::Text;
            31489:
                FieldsType := FieldsType::Code;
            33791:
                FieldsType := FieldsType::BLOB; //Binary
            33793:
                FieldsType := FieldsType::BLOB;
            34047:
                FieldsType := FieldsType::Boolean;
            34559:
                FieldsType := FieldsType::Integer;
            35071:
                FieldsType := FieldsType::Code; //OemCode;
            35583:
                FieldsType := FieldsType::Option;
            36095:
                FieldsType := FieldsType::BigInteger;
            36863:
                FieldsType := FieldsType::Duration;
            37119:
                FieldsType := FieldsType::GUID;
            37375:
                FieldsType := FieldsType::DateTime;
        end;
        AddLoadfields(Fields."No.", Fields.FieldName, FieldsType);
    end;

    procedure AddLoadfields(var FieldRef: FieldRef)
    begin
        AddLoadfields(FieldRef.Number, FieldRef.Name, FieldRef.Type);
    end;

    procedure AddLoadfields(FieldID: Integer; FieldName: Text; FieldType: FieldType)
    var
        IndexOfFieldExt: Integer;
        FieldSQLName: Text;
    begin

        // Calculate SQL field from AL name
        case FieldID of
            2000000001:
                FieldSQLName := '$systemCreatedAt';
            2000000002:
                FieldSQLName := '$systemCreatedBy';
            2000000003:
                FieldSQLName := '$systemModifiedAt';
            2000000004:
                FieldSQLName := '$systemModifiedBy';
            else
                FieldSQLName := EscapeSQLChar(FieldName);
        end;
        IndexOfFieldExt := ListOfFieldInTableExt.IndexOf(FieldID);

        // Get wether the field is in table extension
        if IndexOfFieldExt > 0 then begin
            FieldSQLName := 'ext.[' + FieldSQLName + '$' + DELCHR(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}') + ']';
            RequireExtJoin := true
        end else
            FieldSQLName := 't.[' + FieldSQLName + ']';
        ListSQLFieldsWithAlias.Add(FieldSQLName);

        // Add the field to select
        if Nofields > 0 then
            SQLSelect += ',';
        SQLSelect += FieldSQLName;

        Nofields += 1;
        FieldTypes[Nofields] := FieldType;
    end;
    #endregion

    #region Select
    procedure GetFindSetSQL() SQLString: Text
    begin
        exit(GetFindSetSQL(0));
    end;

    procedure GetFindSetSQL(Top: Integer) SQLString: Text
    var
        TopStr: Text;
    begin
        // Build SQL Query including table extension
        // Based on input table and loadfields
        if Top > 0 then
            TopStr := ' TOP ' + format(Top);

        if RequireExtJoin then
            SQLString := 'SELECT ' + TopStr + SQLSelect + ' ' +
                        StrSubstNo('FROM [%1] AS t ', BaseTableSQLName) + ' ' +
                        StrSubstNo('LEFT JOIN [%1] AS ext ON ', ExtTableSQLName) + GetTableExtJoinCondition(TableID, 't', 'ext')
        else
            SQLString := 'SELECT ' + TopStr + SQLSelect + ' FROM [' + BaseTableSQLName + '] AS t';

        if SQLFilter <> '' then
            SQLString += ' WHERE ' + TopStr + SQLFilter;
    end;
    #endregion

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

    procedure GetSqlConnectionString(ForUpdate: Boolean): Text
    var
        InstanceConfigPath, RootConfigPath, ConfigFilePath : Text;
        DatabaseServer: Text;
        DatabaseInstance: Text;
        DatabaseName: Text;
        DataSource: Text;
        SQLConnectionString: TextBuilder;
        XMLBuffer: Record "XML Buffer" temporary;
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
        XMLBuffer.Load(ConfigFilePath);

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
        SqlConnectionString.Append('MultipleActiveResultSets=False;');
        SqlConnectionString.Append('Packet Size=32767;'); // ← biggest potential win for large data
        if not ForUpdate then
            SqlConnectionString.Append('Enlist=False;');  // free if no transactions
        SqlConnectionString.Append('Min Pool Size=10;');  // warm pool for repeated calls
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