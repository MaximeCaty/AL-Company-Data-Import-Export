#if ONPREM
codeunit 51016 "TOO SQL Helper Bulk Insert"
{
    var
        ConnectionString: Text;
        SQLFilter: Text;
        EmptyGuid: Guid;
        SQLSelect: Text;
        TableCompanyName: Text;
        TableMeta: Record "Table Metadata";
        BaseTableSQLName: Text;
        ExtTableSQLName: Text;
        SQLBulkmporterHelper: DotNet TOOSQLBulkImporterExt;
        RowOpened: Boolean;
        ListOfFieldInTableExt: List of [Integer];
        ListOfFieldInTableExtAppID: List of [Guid];
        ListOfSQLField: List of [Text];
        NoColumns: Integer;
        RowColumns: Integer;
        PIpouBlog: codeunit "TOO Pipou Blob Mgt.";
        EvalDataText: Text;
        EvalDateFormula: DateFormula;
        EvalRecID: RecordId;
        VariantVal: Variant;
        EvalBigInt: BigInteger;
        EvalByte: Byte;
        EvalDate: Date;
        EvalDatetime: DateTime;
        EvalTime: Time;
        EvalGuid: Guid;
        EvalDec: Decimal;
        EvalInt: Integer;
        EmptyRecID: RecordId;
        ZeroByte: Byte;

    procedure Initialize()
    begin
        ClearAll();
        ConnectionString := GetSqlConnectionString();
    end;

    #region Open
    procedure Open(OpenTableID: Integer; FromCompanyName: Text)
    var
        SourceTableName: Text;
        Fields: Record Field;
        PublishedApp: Record "Published Application";
        AllObj: Record AllObj;
        TableOriginalApp: Record "Published Application";
    begin
        SQLBulkmporterHelper := SQLBulkmporterHelper.BulkImporterExt();
        RowOpened := false;
        TableMeta.Get(OpenTableID);
        AllObj.get(AllObj."Object type"::Table, OpenTableID);
        TableOriginalApp.Get(AllObj."App Runtime Package ID");
        SQLFilter := '';
        SQLSelect := '';
        TableCompanyName := FromCompanyName;
        NoColumns := 0;
        clear(ListOfFieldInTableExt);
        clear(ListOfFieldInTableExtAppID);
        clear(ListOfSQLField);

        // Get SQL Table Name
        SourceTableName := EscapeSQLChar(TableMeta.Name);
        if TableMeta.DataPerCompany then
            BaseTableSQLName := StrSubstNo('%1$%2$%3', TableCompanyName, SourceTableName, DELCHR(TableOriginalApp."ID", '=', '{}').ToLower())
        else
            BaseTableSQLName := StrSubstNo('%1$%2', SourceTableName, DELCHR(TableOriginalApp."ID", '=', '{}').ToLower());
        ExtTableSQLName := BaseTableSQLName + '$ext';

        // Get list of fields stored in extension table
        Fields.SetLoadFields("No.", "App Runtime Package ID");
        Fields.SetRange(TableNo, OpenTableID);
        Fields.SetRange(Class, Fields.Class::Normal);
        Fields.SetFilter("App Runtime Package ID", '<>%1', EmptyGuid);
        if Fields.FindSet() then
            repeat
                // Check that the field is from different App ID than base table (tableextension in the same project are stored in base table)
                PublishedApp.SetLoadFields(ID);
                PublishedApp.SetFilter(ID, '<>%1', TableOriginalApp."ID");
                PublishedApp.SetRange("Runtime Package ID", Fields."App Runtime Package ID");
                PublishedApp.SetRange(Installed, true);
                if PublishedApp.FindFirst() then begin
                    ListOfFieldInTableExt.Add(Fields."No.");
                    ListOfFieldInTableExtAppID.Add(PublishedApp.ID);
                end;
            until Fields.Next() = 0;

        BeginRow(); // prepare first row
    end;
    #endregion

    #region Column
    procedure AddBulkColumn(FieldRef: FieldRef; IsPartOfPK: Boolean)
    var
        Type: Text;
        IndexOfFieldExt: Integer;
    begin
        case FieldRef.Type of
            FieldRef.Type::Text,
            FieldRef.Type::Code:
                Type := 'String';
            FieldRef.Type::Boolean,
            FieldRef.Type::Integer,
            FieldRef.Type::Option:
                Type := 'Int32';
            FieldRef.Type::BigInteger,
            FieldRef.Type::Duration:
                Type := 'Int64';
            FieldRef.Type::Decimal:
                Type := 'Decimal';
            FieldRef.Type::Time:
                Type := 'DateTime';
            FieldRef.Type::Date:
                Type := 'DateTime';
            FieldRef.Type::DateTime:
                Type := 'DateTime';
            FieldRef.Type::Guid,
            FieldRef.Type::Media,
            FieldRef.Type::MediaSet:
                Type := 'GUID';
            FieldRef.Type::Blob:
                Type := 'blob';
        // TableFilter / RecordID / DateFormula types are in BC runtime dll
        end;
        IndexOfFieldExt := ListOfFieldInTableExt.IndexOf(FieldRef.Number);
        if IndexOfFieldExt > 0 then begin
            SQLBulkmporterHelper.AddColumn(EscapeSQLChar(FieldRef.Name) + '$' + DELCHR(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}').Tolower(), Type, IsPartOfPK);
            ListOfSQLField.Add(EscapeSQLChar(FieldRef.Name) + '$' + DELCHR(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}').ToLower() + ' : ' + Type);
        end else begin
            // System audit field are in SQl with starting '$' + lower case 's'
            case FieldRef.Number of
                2000000001:
                    SQLBulkmporterHelper.AddColumn('$systemCreatedAt', 'DateTime', IsPartOfPK);
                2000000002:
                    SQLBulkmporterHelper.AddColumn('$systemCreatedBy', 'GUID', IsPartOfPK);
                2000000003:
                    SQLBulkmporterHelper.AddColumn('$systemModifiedAt', 'DateTime', IsPartOfPK);
                2000000004:
                    SQLBulkmporterHelper.AddColumn('$systemModifiedBy', 'GUID', IsPartOfPK);
                else
                    SQLBulkmporterHelper.AddColumn(EscapeSQLChar(FieldRef.Name), Type, IsPartOfPK);
            end;
            ListOfSQLField.Add(EscapeSQLChar(FieldRef.Name) + ' : ' + Type);
        end;
        NoColumns += 1;
    end;

    procedure AddBulkColumnAudits()
    begin
        SQLBulkmporterHelper.AddColumn('$systemCreatedAt', 'DateTime');
        SQLBulkmporterHelper.AddColumn('$systemCreatedBy', 'GUID');
        SQLBulkmporterHelper.AddColumn('$systemModifiedAt', 'DateTime');
        SQLBulkmporterHelper.AddColumn('$systemModifiedBy', 'GUID');
    end;
    #endregion

    #region Add BIN Value
    local procedure AddBulkBlobValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        Length: Integer;
        TempBlob: Codeunit "Temp Blob";
        OutStr: OutStream;
        BlobBytes: DotNet Array; // System.Array
        DotNetType: DotNet Type; // System.Type
        MemoryStream: DotNet MemoryStream;
        BlobInStr: InStream;
    begin
        // dot net bulk insert does not support stream, we need to convert it to Byte array
        InStr.Read(Length);
        if Length <= 0 then begin
            // Create an empty binary array
            BlobBytes := BlobBytes.CreateInstance(DotNetType.GetType('System.Byte'), 0);
            SQLBulkmporterHelper.AddRowValue(BlobBytes, ColumnZeroBaseIndex);
            exit;
        end;
        // 2. Copy exactly 'Length' bytes into TempBlob
        TempBlob.CreateOutStream(OutStr);
        CopyStream(OutStr, InStr, Length);

        // 3. Copy the blob to dot net memory stream
        TempBlob.CreateInStream(BlobInStr);
        MemoryStream := MemoryStream.MemoryStream();
        CopyStream(MemoryStream, BlobInStr);

        // 4. Send Byte[] to bulk insert
        SQLBulkmporterHelper.AddRowValueBlob(MemoryStream.ToArray(), ColumnZeroBaseIndex);
    end;

    local procedure AddBulkMediaValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        VariantVal: Variant;
        Guid: Guid;
    begin
        PIpouBlog.ImportMediaBinary(Guid, InStr);
        VariantVal := Guid;
        SQLBulkmporterHelper.AddRowValue(VariantVal, ColumnZeroBaseIndex);
    end;

    local procedure AddBulkMediaSetValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        VariantVal: Variant;
        Guid: Guid;
    begin
        PIpouBlog.ImportMediaSetBinary(Guid, InStr);
        VariantVal := Guid;
        SQLBulkmporterHelper.AddRowValue(VariantVal, ColumnZeroBaseIndex);
    end;

    local procedure AddBulkRecIDValueToSQLBin(var RecID: RecordId)
    var
        MemoryStream: DotNet MemoryStream;
        TempBlob: Codeunit "Temp Blob";
        RecIDOutStr: OutStream;
        RecIDInStr: InStream;
    begin
        clear(TempBlob);
        RecIDOutStr := TempBlob.CreateOutStream();
        // Write RecordID to SQL binary format in outstream
        RecordIDToSQLBinaryValue(RecID, RecIDOutStr);
        // Convert Copy the Blob to MemoryStream
        MemoryStream := MemoryStream.MemoryStream();
        RecIDInStr := TempBlob.CreateInStream();
        CopyStream(MemoryStream, RecIDInStr);
        // Write Byte[] from MemmoryStream
        SQLBulkmporterHelper.AddRowValue(MemoryStream.ToArray(), RowColumns);
        MemoryStream.Dispose();
    end;

    local procedure RecordIDToSQLBinaryValue(RecID: RecordId; var OutStr: OutStream)
    var
        RecRef: RecordRef;
        PK: KeyRef;
        I: Integer;
    begin
        /*
        Decompiled from Microsoft.Dynamics.Nav.Runtime.NavRecordID
        [4 bytes]   TableNo (little-endian int32)
        repeated:
            [2 bytes]  NavType code (as unsigned short little-endian)
            [N bytes]  Field value bytes (length depends on type)
        [2 bytes]   Terminator = 00 00
        */
        if RecID = EmptyRecID then begin
            // 0 int + ending double 0 byte = 6 bytes
            OutStr.Write(I); // Zero table as int
            OutStr.Write(ZeroByte);
            OutStr.Write(ZeroByte);
            exit;
        end;

        OutStr.Write(RecID.TableNo);
        RecRef := RecID.GetRecord();
        PK := RecRef.KeyIndex(1);
        // Loop through the Record ID PK fields
        for I := 1 to PK.FieldCount do begin
            // Write each PK field type as NavType unsigned short
            WriteUInt16LE(FieldTypeToNavType(PK.FieldIndex(I).Type), OutStr);
            // Write value
            case PK.FieldIndex(I).Type of
                FieldType::Text,
                FieldType::Code,
                FieldType::DateFormula,
                FieldType::Boolean,
                FieldType::Integer,
                FieldType::Option,
                FieldType::Date,
                FieldType::Time,
                FieldType::Duration,
                FieldType::BigInteger,
                FieldType::Decimal,
                FieldType::Guid,
                FieldType::DateTime:
                    OutStr.Write(PK.FieldIndex(I).Value);
                FieldType::RecordId:
                    begin
                        EvalRecID := PK.FieldIndex(I).Value;
                        RecordIDToSQLBinaryValue(EvalRecID, OutStr);
                    end;
            end;
        end;
        // Ending double 0 bytes
        OutStr.Write(ZeroByte);
        OutStr.Write(ZeroByte);
    end;

    local procedure FieldTypeToNavType(FieldType: FieldType) NavTypeValue: Integer
    begin
        // List decompiled from c# enum Microsoft.Dynamics.Nav.Types.NavType 
        // Seem to be NclType + 1
        case FieldType of
            FieldType::Integer:
                NavTypeValue := 34560;
            FieldType::Boolean:
                NavTypeValue := 34048;
            FieldType::Code:
                NavTypeValue := 31490;
            FieldType::Text:
                NavTypeValue := 31489;
            FieldType::Date:
                NavTypeValue := 11776;
            FieldType::Time:
                NavTypeValue := 11777;
            FieldType::Decimal:
                NavTypeValue := 12800;
            FieldType::Option:
                NavTypeValue := 35584;
            FieldType::DateFormula:
                NavTypeValue := 11798;
            FieldType::Guid:
                NavTypeValue := 37120;
            FieldType::BigInteger:
                NavTypeValue := 36096;
            FieldType::Duration:
                NavTypeValue := 36864;
            FieldType::DateTime:
                NavTypeValue := 37376;
            FieldType::Media:
                NavTypeValue := 26208;
            FieldType::MediaSet:
                NavTypeValue := 26209;
            FieldType::Blob:
                NavTypeValue := 33794;
            FieldType::RecordId:
                NavTypeValue := 4989;
            FieldType::TableFilter:
                NavTypeValue := 4913;
            else
                Error('Unsupported NCL Field Type conversion : %1', FieldType);
        end;
    end;

    local procedure WriteUInt16LE(Value: Integer; var OutStr: OutStream)
    var
        Lo: Byte;
        Hi: Byte;
    begin
        // Value must be 0..65535
        Lo := Value mod 256;
        Hi := (Value div 256) mod 256;
        OutStr.Write(Lo);
        OutStr.Write(Hi);
    end;

    procedure AddBulkValueFromBin(var FieldType: enum "TOO Fields Types"; var FieldLen: Integer; var InStr: InStream)
    begin
        case FieldType of
            FieldType::BLOB:
                AddBulkBlobValueFromBin(InStr, RowColumns);
            FieldType::Media:
                AddBulkMediaValueFromBin(InStr, RowColumns);
            FieldType::MediaSet:
                AddBulkMediaSetValueFromBin(InStr, RowColumns);

            FieldType::Text,
            FieldType::Code:
                begin
                    InStr.Read(EvalDataText);
                    SQLBulkmporterHelper.AddRowValue(copystr(EvalDataText, 1, FieldLen), RowColumns);
                end;

            FieldType::DateFormula:
                begin
                    InStr.Read(EvalDataText);
                    if not EvalDataText.StartsWith('<') then
                        Evaluate(EvalDateFormula, '<' + EvalDataText + '>')
                    else
                        Evaluate(EvalDateFormula, EvalDataText);
                    VariantVal := EvalDateFormula;
                    SQLBulkmporterHelper.AddRowValue(VariantVal, RowColumns);
                end;

            FieldType::RecordId:
                begin
                    InStr.Read(EvalDataText);
                    if EvalDataText = '' then
                        EvalRecID := EmptyRecID
                    else
                        if not Evaluate(EvalRecID, EvalDataText.Replace('{', '').Replace('}', '')) then
                            EvalRecID := EmptyRecID; // Invalid Table or PK, cant parse RecordID
                    // Convert then write RecordID to SQL binary format
                    AddBulkRecIDValueToSQLBin(EvalRecID);
                end;

            FieldType::Duration:
                begin
                    InStr.Read(EvalBigInt);
                    SQLBulkmporterHelper.AddRowValue(EvalBigInt, RowColumns);
                end;

            FieldType::Boolean:
                begin
                    InStr.Read(EvalByte);
                    if (EvalByte = 1) then
                        SQLBulkmporterHelper.AddRowValue(true, RowColumns)
                    else
                        SQLBulkmporterHelper.AddRowValue(false, RowColumns);
                end;

            FieldType::Date:
                begin
                    InStr.Read(EvalDate);
                    if EvalDate = 0D then
                        SQLBulkmporterHelper.AddRowValueALDate(0, 0, 0, RowColumns)
                    else begin
                        // EvalDate = ClosingDate(EvalDate) only for closing dates → flag stored as 23:59:59 in SQL
                        SQLBulkmporterHelper.AddRowValueALDate(Date2DMY(EvalDate, 3), Date2DMY(EvalDate, 2), Date2DMY(EvalDate, 1), RowColumns, EvalDate = ClosingDate(EvalDate))
                    end;
                end;

            FieldType::Time:
                begin
                    InStr.Read(EvalTime);
                    if EvalTime = 0T then
                        SQLBulkmporterHelper.AddRowValueALTime(0DT, RowColumns)
                    else
                        SQLBulkmporterHelper.AddRowValueALTime(CreateDateTime(DMY2Date(1, 1, 1753), EvalTime), RowColumns);
                end;

            FieldType::DateTime:
                begin
                    InStr.Read(EvalDateTime);
                    SQLBulkmporterHelper.AddRowValue(EvalDateTime, RowColumns);
                end;

            FieldType::Guid:
                begin
                    InStr.Read(EvalGuid);
                    SQLBulkmporterHelper.AddRowValue(EvalGuid, RowColumns);
                end;

            FieldType::Decimal:
                begin
                    InStr.Read(EvalDec);
                    SQLBulkmporterHelper.AddRowValue(EvalDec, RowColumns);
                end;

            FieldType::Option,
            FieldType::Integer:
                begin
                    InStr.Read(EvalInt);
                    SQLBulkmporterHelper.AddRowValue(EvalInt, RowColumns);
                end;

            FieldType::BigInteger:
                begin
                    InStr.Read(EvalBigInt);
                    SQLBulkmporterHelper.AddRowValue(EvalBigInt, RowColumns);
                end;
            else
                Error('Unsupported field type %1', FieldType)
        end;
        RowColumns += 1;
    end;
    #endregion

    #region Add FIELD Value
    procedure AddBulkRowValue(FieldValue: FieldRef; IsPartOfPK: Boolean)
    var
        VariantVal: Variant;
        Guid: Guid;
        BigInt: BigInteger;
    begin
        // Trnasform specific value for SQL interop
        case FieldValue.Type of
            // SQL datetime storage from date, time and datetime, require convert to utc+manualy empty date
            FieldValue.Type::Date:
                begin
                    EvalDate := FieldValue.Value;
                    if EvalDate = 0D then
                        SQLBulkmporterHelper.AddRowValueALDate(0, 0, 0, RowColumns)
                    else begin
                        // EvalDate = ClosingDate(EvalDate) only for closing dates → flag stored as 23:59:59 in SQL
                        SQLBulkmporterHelper.AddRowValueALDate(Date2DMY(EvalDate, 3), Date2DMY(EvalDate, 2), Date2DMY(EvalDate, 1), RowColumns, EvalDate = ClosingDate(EvalDate));
                    end;
                end;
            FieldValue.Type::DateTime:
                begin
                    EvalDatetime := FieldValue.Value;
                    SQLBulkmporterHelper.AddRowValue(EvalDateTime, RowColumns);
                end;
            FieldValue.Type::Time:
                begin
                    EvalTime := FieldValue.Value;
                    if EvalTime = 0T then
                        SQLBulkmporterHelper.AddRowValueALTime(0DT, RowColumns)
                    else
                        SQLBulkmporterHelper.AddRowValueALTime(CreateDateTime(DMY2Date(1, 1, 1753), EvalTime), RowColumns);
                end;
            FieldValue.Type::Duration:
                begin
                    BigInt := FieldValue.Value;
                    SQLBulkmporterHelper.AddRowValue(BigInt, RowColumns);
                end;
            FieldValue.Type::Media,
            FieldValue.Type::MediaSet:
                begin
                    Guid := FieldValue.Value;
                    SQLBulkmporterHelper.AddRowValue(Guid, RowColumns);
                end;
            else begin
                VariantVal := FieldValue.Value;
                SQLBulkmporterHelper.AddRowValue(VariantVal, RowColumns);
            end;
        end;
        RowColumns += 1;
    end;
    #endregion

    procedure AddBulkRowValueAudit(CreatedAt: DateTime; CreatedBy: Guid; ModifiedAt: DateTime; ModifiedBy: Guid)
    begin
        // Zero based column for dotnet
        SQLBulkmporterHelper.AddRowValue(CreatedAt, RowColumns);
        SQLBulkmporterHelper.AddRowValue(CreatedBy, RowColumns + 1);
        SQLBulkmporterHelper.AddRowValue(ModifiedAt, RowColumns + 2);
        SQLBulkmporterHelper.AddRowValue(ModifiedBy, RowColumns + 3);
    end;

    #region Insert Row
    procedure Insert()
    var
        ErrColMisMatch: Label 'The number of values passed is different than the column definition.';
    begin
        if (RowColumns <> NoColumns) then
            Error(ErrColMisMatch);
        SQLBulkmporterHelper.EndRow();
        RowOpened := false;
        RowColumns := 0;
        BeginRow(); // prepare next row if any
    end;

    #region Send Bulk
    [TryFunction]
    procedure CommitBulkInserts(UseTableLock: Boolean)
    begin
        // UseTableLock = false → per-row locks, lets several threads bulk-insert the same table at once
        SQLBulkmporterHelper.WriteToServer(GetSqlConnectionString(), BaseTableSQLName, UseTableLock);
    end;
    #endregion
    #endregion

    #region internal
    local procedure BeginRow()
    begin
        if not RowOpened then begin
            SQLBulkmporterHelper.BeginRow();
            RowOpened := true;
            RowColumns := 0;
        end;
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

    local procedure GetSqlConnectionString(): Text
    var
        Sqlhelper: Codeunit "TOO SQL Helper FindSet";
    begin
        if ConnectionString = '' then
            ConnectionString := Sqlhelper.GetSqlConnectionString(true);
        exit(ConnectionString);
    end;
    #endregion
}
#endif
