codeunit 51004 "TOO Pipou Mgt."
{
    // force permission on protected tables to write into
    Permissions = tabledata 52 = rimd, tabledata "Vendor Ledger Entry" = rimd, tabledata "FA Ledger Entry" = rimd, tabledata "Job Ledger Entry" = rimd, tabledata "Item Ledger Entry" = rimd,
     tabledata "Res. Ledger Entry" = rimd, tabledata "Check Ledger Entry" = rimd, tabledata "Cust. Ledger Entry" = rimd, tabledata "Service Ledger Entry" = rimd,
     tabledata "Capacity Ledger Entry" = rimd, tabledata "Employee Ledger Entry" = rimd, tabledata "Warranty Ledger Entry" = rimd, tabledata "Maintenance Ledger Entry" = rimd,
     tabledata "Bank Account Ledger Entry" = rimd, tabledata "Ins. Coverage Ledger Entry" = rimd, tabledata "Payable Vendor Ledger Entry" = rimd, tabledata "Phys. Inventory Ledger Entry" = rimd,
     tabledata "Payable Employee Ledger Entry" = rimd, tabledata "Detailed Employee Ledger Entry" = rimd, tabledata "Detailed Cust. Ledg. Entry" = rimd, tabledata "Detailed Vendor Ledg. Entry" = rimd,
     tabledata "Sales Invoice Header" = rimd, tabledata "Sales Invoice Line" = rimd, tabledata "Sales Shipment Header" = rimd, tabledata "Sales Shipment Line" = rimd,
     tabledata "Sales Cr.Memo Header" = rimd, tabledata "Sales Cr.Memo Line" = rimd, tabledata "Purch. Cr. Memo Hdr." = rimd, tabledata "Purch. Cr. Memo Line" = rimd,
     tabledata "Purch. Inv. Header" = rimd, tabledata "Purch. Inv. Line" = rimd, tabledata "Purch. Rcpt. Header" = rimd, tabledata "Purch. Rcpt. Line" = rimd,
     tabledata "Purchase Header Archive" = rimd, tabledata "Sales Line Archive" = rimd, tabledata "Sales Header Archive" = rimd, tabledata "Purchase Line Archive" = rimd,
     tabledata "Sales Comment Line Archive" = rimd, tabledata "Purch. Comment Line Archive" = rimd, tabledata "Workflow Step Argument Archive" = rimd, tabledata "Workflow Record Change Archive" = rimd,
     tabledata "Workflow Step Instance Archive" = rimd, tabledata "G/L Entry" = rimd, tabledata "Approval Entry" = rimd, tabledata "Warehouse Entry" = rimd,
     tabledata "Value Entry" = rimd, tabledata "Item Register" = rimd, tabledata "G/L Register" = rimd, tabledata "Vat Entry" = rimd, tabledata "Dimension Set Entry" = rimd,
     tabledata "Service Invoice Header" = rimd, tabledata "Service Cr.Memo Header" = rimd, TableData "Issued Reminder Header" = rimd, tabledata "Issued Reminder Line" = rimd, TableData "Issued Fin. Charge Memo Header" = rimd,
     tabledata "G/L Entry - VAT Entry Link" = rimd, tabledata "Item Application Entry" = rimd, tabledata "Item Application Entry History" = rimd,
     tabledata "Return Shipment Header" = rimd, tabledata "Return Shipment Line" = rimd, tabledata "Return Receipt Header" = rimd, tabledata "Return Receipt Line" = rimd,
     tabledata "Invt. Receipt Header" = rimd, tabledata "Invt. Receipt Line" = rimd, tabledata "Invt. Shipment Header" = rimd, tabledata "Invt. Shipment Line" = rimd,
     tabledata "Pstd. Phys. Invt. Record Hdr" = rimd, tabledata "Pstd. Phys. Invt. Record Line" = rimd, tabledata "Pstd. Phys. Invt. Order Hdr" = rimd, tabledata "Pstd. Phys. Invt. Order Line" = rimd,
     tabledata "Bank Account Statement Line" = rimd, tabledata "Change Log Entry" = rimd, tabledata "Posted Approval Entry" = rimd, tabledata "FA Register" = rimd, tabledata "Post Value Entry to G/L" = rimd,
     tabledata "Job Register" = rimd, tabledata "Reminder/Fin. Charge Entry" = rmid, tabledata "Posted Approval Comment Line" = rmid, tabledata "Dimension Set Tree Node" = rmid, tabledata "Cancelled Document" = rmid;


    procedure Initialize(SetBlobMaxSize: Integer; ClassifiedDataExportHandling: Option "Keep","Empty","Randomize")
    var
        typehelp: Codeunit "Type Helper";
    begin
        CR[1] := 13;
        OneByte := 1;
        LF := typehelp.LFSeparator();
        Logentry := 0;
        BlobMaxSize := SetBlobMaxSize;
        ClassifiedDataHandling := ClassifiedDataExportHandling;
        AllALTypes.Open(Database::"TOO All Types");
        DefTextFieldRef := AllALTypes.Field(10);
        DefCodeFieldRef := AllALTypes.Field(11);
        DefDateFieldRef := AllALTypes.Field(12);
        DefTimeFieldRef := AllALTypes.Field(13);
        DefDateTimeFieldRef := AllALTypes.Field(14);
        DefIntFieldRef := AllALTypes.Field(15);
        DefBigIntFieldRef := AllALTypes.Field(16);
        DefDecFieldRef := AllALTypes.Field(17);
        DefDurFieldRef := AllALTypes.Field(18);
        DefRecIDFieldRef := AllALTypes.Field(19);
        DefDateFormulaFieldRef := AllALTypes.Field(20);
    end;

    procedure GetMajorBCVersion(): Integer
    var
        AppSysConstants: Codeunit "Application System Constants";
        VersionText: Text;
        Major: Integer;
        DotPos: Integer;
    begin
        VersionText := AppSysConstants.ApplicationVersion();
        DotPos := StrPos(VersionText, '.');
        if DotPos > 1 then
            if Evaluate(Major, CopyStr(VersionText, 1, DotPos - 1)) then
                exit(Major);

        exit(0); // fallback
    end;

    #region ProgressBar
    procedure ProgressBar(ProgressPercent: Decimal) AsciiResult: Text
    var
        i: Integer;
        ProgressChar: Integer;
    begin
        ProgressChar := Round(ProgressPercent * 24, 1, '<') + 1;
        for i := 1 to 24 do begin
            if i < ProgressChar then
                AsciiResult += '▰'
            else
                if i = ProgressChar then
                    AsciiResult += '▴'
                else
                    AsciiResult += '▱';
            if i = 12 then // half of 25
                AsciiResult += Format(Round(ProgressPercent * 100, 1)).PadLeft(2, '0') + '%';
        end;
    end;
    #endregion

    #region Log
    // Status : " ","Warning","Error","Information"
    // Actions : " ","Clear Table","Insert Record","Parsing Field",Commit,AL Code
    procedure LogALErrorMessage(var Chunk: Record "TOO Pipou Archive Files"; ErrMsg: Text; CallStack: Text)
    var
        EmptyRecID: RecordId;
    begin
        LogMessage(Chunk, EmptyRecID, 2, 5, ErrMsg, CallStack)
    end;

    procedure LogCommitErrorMessage(var Chunk: Record "TOO Pipou Archive Files"; ErrMsg: Text)
    var
        EmptyRecID: RecordId;
    begin
        LogMessage(Chunk, EmptyRecID, 2, 4, ErrMsg, '')
    end;

    procedure LogInsertRecErrorMessage(var Chunk: Record "TOO Pipou Archive Files"; RecID: RecordId; ErrMsg: Text)
    begin
        LogMessage(Chunk, RecID, 2, 2, ErrMsg, '')
    end;

    procedure LogParsingFieldErrorMessage(var Chunk: Record "TOO Pipou Archive Files"; RecID: RecordId; ErrMsg: Text)
    begin
        LogMessage(Chunk, RecID, 2, 3, ErrMsg, '')
    end;

    procedure LogParsingFieldWarningMessage(var Chunk: Record "TOO Pipou Archive Files"; RecID: RecordId; ErrMsg: Text)
    begin
        LogMessage(Chunk, RecID, 1, 3, ErrMsg, '')
    end;

    procedure LogClearTableErrorMessage(var Chunk: Record "TOO Pipou Archive Files"; ErrMsg: Text)
    var
        RecID: RecordId;
    begin
        LogMessage(Chunk, RecID, 2, 1, ErrMsg, '')
    end;


    local procedure LogMessage(var Chunk: Record "TOO Pipou Archive Files"; RecID: RecordId; Status: Option; Action: Option; ErrMsg: Text; CallStack: text)
    var
        Log: Record "TOO Pipou Import Log";
    begin
        if Logentry = 0 then begin
            Log.SetRange("Archive Name", Chunk."Archive Name");
            Log.SetRange("Archive ID", Chunk."Archive ID");
            if Log.FindLast() then
                Logentry := Log."Entry No." + 1
            else
                Logentry := 1;
        end;
        Log.Init();
        Log."Archive Name" := Chunk."Archive Name";
        Log."Archive ID" := Chunk."Archive ID";
        Log."Entry No." := Logentry;
        Log."Thread No." := Chunk."Affected Thread";
        Log."Chunk Entry No." := Chunk."File Name";
        log."Record ID" := RecID;
        log.Status := Status;
        log.Action := Action;
        log.Message := Copystr(ErrMsg, 1, 2048);
        log.CallStack := CopyStr(CallStack, 1, 2048);
        log."Table ID" := Chunk."Table ID";
        log."Table Name" := Chunk."Table Name";
        log.Insert(true);
        Logentry += 1;
    end;
    #endregion

    [TryFunction()]
    procedure TryClearTableContent(var RecReftoClear: RecordRef)
    begin
        RecReftoClear.DeleteAll();
    end;

    [TryFunction()]
    procedure TryInsertRecRef(var RecRef: RecordRef)
    begin
        RecRef.Insert(false);
    end;

    #region Write Bin
    procedure WriteFieldBinaryData(var OutStr: OutStream; FieldRef: FieldRef): Boolean // return if value is undefined/default value (true) or (false)
    begin
        case FieldRef.Type of

            FieldRef.Type::BLOB:
                begin
                    if BlobMgt.ExportBlobFieldBinary(FieldRef, OutStr, BlobMaxSize) > 0 then
                        exit(false);
                end;

            FieldRef.Type::Media:
                begin
                    BlobMgt.ExportMediaFieldBinary(FieldRef.Value, OutStr);
                    exit(IsNullGuid(FieldRef.Value));
                end;

            FieldRef.Type::MediaSet:
                begin
                    BlobMgt.ExportMediaSetFieldBinary(FieldRef.Value, OutStr);
                    exit(IsNullGuid(FieldRef.Value));
                end;

            FieldRef.Type::Text:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefTextFieldRef.Value);
                end;

            FieldRef.Type::Code:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefCodeFieldRef.Value);
                end;

            FieldRef.Type::DateFormula:
                begin
                    OutStr.Write(format(FieldRef.Value, 0, 9));
                    exit(FieldRef.Value = DefDateFormulaFieldRef.Value);
                end;

            FieldRef.Type::RecordId:
                begin
                    OutStr.Write(format(FieldRef.Value, 0, 9));
                    exit(FieldRef.Value = DefRecIDFieldRef.Value);
                end;

            FieldRef.Type::Duration:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value <> DefDurFieldRef.Value);
                end;

            FieldRef.Type::Time:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefTimeFieldRef.Value);
                end;

            FieldRef.Type::Date:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefDateFieldRef.Value);
                end;

            FieldRef.Type::DateTime:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefDateTimeFieldRef.Value);
                end;

            FieldRef.Type::Boolean:
                begin
                    EvalBool := FieldRef.Value;
                    if EvalBool then begin
                        OutStr.Write(OneByte);
                        exit(false);
                    end else
                        OutStr.Write(ZeroByte);
                end;

            FieldRef.Type::Option,
            FieldRef.Type::Integer:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefIntFieldRef.Value);
                end;

            FieldRef.Type::BigInteger:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefBigIntFieldRef.Value);
                end;

            FieldRef.Type::Decimal:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(FieldRef.Value = DefDecFieldRef.Value);
                end;

            FieldRef.Type::Guid:
                begin
                    OutStr.Write(FieldRef.Value);
                    exit(IsNullGuid(FieldRef.Value));
                end else
                        Error('Field type unsupported for binary writting : %1', FieldRef.Type); // Unknown data type ?
        end;
    end;
    #endregion

    #region Write Empty
    procedure WriteBinaryEmptyField(FieldRef: FieldRef; var OutStr: OutStream)
    begin
        case FieldRef.Type of
            FieldRef.Type::Text,
            FieldRef.Type::Code,
            FieldRef.Type::DateFormula,
            FieldRef.Type::RecordId:
                OutStr.Write('');

            FieldRef.Type::BLOB,
            FieldRef.Type::MediaSet,
            FieldRef.Type::Media:
                OutStr.Write(0);

            FieldRef.Type::Integer,
            FieldRef.Type::Option:
                OutStr.Write(0);

            FieldRef.Type::BigInteger,
            FieldRef.Type::Duration:
                OutStr.Write(0L);

            FieldRef.Type::Date:
                OutStr.Write(0);

            FieldRef.Type::Time:
                OutStr.Write(0);

            FieldRef.Type::DateTime:
                OutStr.Write(0L);

            FieldRef.Type::Boolean:
                OutStr.Write(ZeroByte);

            FieldRef.Type::Decimal:
                OutStr.Write(EmptyDecimal); // 12 bits

            FieldRef.Type::Guid:
                OutStr.Write(EmptyGuid); // 16 bits

            else
                Error('Field type %1 is not supported for empty binary writting', FieldRef.Type); // Unknown data type ?
        end;
    end;
    #endregion



    #region Skip Bytes
    [TryFunction]
    procedure SkipBinaryBytesBCField(FieldTypeAsInt: Integer; var InStr: InStream)
    var
        Text: Text;
        MediaI: Integer;
        MediaCount: Integer;
    begin
        // Skip/Read instream byte without handling the value (when no mapping available for import)
        case FieldTypeAsInt of
            "TOO Fields Types"::BLOB:
                begin
                    InStr.Read(EvalInt);
                    InStr.Position := Min(InStr.Position + EvalInt, InStr.Length);
                end;

            "TOO Fields Types"::Media:
                begin
                    // Length, Guid, Mime Type, Width, Height, Desciption, Content
                    InStr.Read(EvalInt);
                    if EvalInt > 0 then begin
                        InStr.Position := InStr.Position + 16; // media guid
                        InStr.Read(Text); // Mime Type
                        InStr.Position := InStr.Position + 8; // Width, Height 2 x Integer (2x4=8)
                        InStr.Read(Text);
                        InStr.Position := Min(InStr.Position + EvalInt, InStr.Length); // skip the blob
                    end;
                end;
            "TOO Fields Types"::MediaSet:
                begin
                    // Media count, MediaSet ID, (Media Index, Length, Guid, Mime Type, Width, Height, Desciption, Content)[n]
                    InStr.Read(MediaCount);
                    if MediaCount > 0 then begin
                        InStr.Position := InStr.Position + 16; // mediaset guid
                        for MediaI := 1 to MediaCount do begin
                            InStr.Position := InStr.Position + 4; // media index
                            InStr.Read(EvalInt); // length
                            InStr.Position := InStr.Position + 16; // media guid
                            InStr.Read(Text); // Mime Type
                            InStr.Position := InStr.Position + 8; // Width, Height 2 x Integer (2x4=8)
                            InStr.Read(Text); // description
                            InStr.Position := Min(InStr.Position + EvalInt, InStr.Length); // skip the blob
                        end;
                    end;
                end;

            "TOO Fields Types"::Text,
            "TOO Fields Types"::Code,
            "TOO Fields Types"::DateFormula,
            "TOO Fields Types"::RecordId:
                InStr.Read(Text);

            "TOO Fields Types"::Duration:
                InStr.Position := Min(InStr.Position + 8, InStr.Length);

            "TOO Fields Types"::Date:
                InStr.Position := Min(InStr.Position + 4, InStr.Length);

            "TOO Fields Types"::Time:
                InStr.Position := Min(InStr.Position + 4, InStr.Length);

            "TOO Fields Types"::DateTime:
                InStr.Position := Min(InStr.Position + 8, InStr.Length);

            // Fixed lengths skip :
            "TOO Fields Types"::Boolean:
                InStr.Position := Min(InStr.Position + 1, InStr.Length);

            "TOO Fields Types"::Guid:
                InStr.Position := Min(InStr.Position + 16, InStr.Length);

            "TOO Fields Types"::Decimal:
                InStr.Position := Min(InStr.Position + 12, InStr.Length);

            "TOO Fields Types"::Option,
            "TOO Fields Types"::Integer:
                InStr.Position := Min(InStr.Position + 4, InStr.Length);

            "TOO Fields Types"::BigInteger:
                InStr.Position := Min(InStr.Position + 8, InStr.Length);

            // Unknown ???
            else
                InStr.Read(Text);
        end;
    end;
    #endregion

    #region Parse Bin
    [TryFunction]
    procedure EvaluateBinaryToBCField(var FieldRef: FieldRef; var InStr: InStream)
    begin
        case FieldRef.Type of

            FieldRef.Type::BLOB:
                BlobMgt.ImportBlobBinData(FieldRef, InStr);

            FieldRef.Type::Media:
                begin
                    BlobMgt.ImportMediaBinary(EvalGuid, InStr);
                    FieldRef.Value := EvalGuid;
                end;

            FieldRef.Type::MediaSet:
                begin
                    BlobMgt.ImportMediaSetBinary(EvalGuid, InStr);
                    FieldRef.Value := EvalGuid;
                end;

            FieldRef.Type::Text,
            FieldRef.Type::Code:
                begin
                    InStr.Read(TextData);
                    FieldRef.Value := copystr(TextData, 1, FieldRef.Length);
                end;

            FieldRef.Type::DateFormula:
                begin
                    InStr.Read(TextData);
                    if not TextData.StartsWith('<') then
                        Evaluate(EvalDateFormula, '<' + TextData + '>')
                    else
                        Evaluate(EvalDateFormula, TextData);
                    FieldRef.Value := EvalDateFormula;
                end;

            FieldRef.Type::RecordId:
                begin
                    InStr.Read(TextData);
                    Evaluate(EvalRecID, TextData.Replace('{', '').Replace('}', ''));
                    FieldRef.Value := EvalRecID;
                end;

            FieldRef.Type::Duration:
                begin
                    InStr.Read(EvalDuration);
                    FieldRef.Value := EvalDuration;
                end;

            FieldRef.Type::Boolean:
                begin
                    InStr.Read(EvalByte);
                    if (EvalByte = 1) then
                        FieldRef.Value := true;
                end;

            FieldRef.Type::Date:
                begin
                    InStr.Read(EvalDate);
                    FieldRef.Value := EvalDate;
                end;

            FieldRef.Type::Time:
                begin
                    InStr.Read(EvalTime);
                    FieldRef.Value := EvalTime;
                end;

            FieldRef.Type::DateTime:
                begin
                    InStr.Read(EvalDateTime);
                    FieldRef.Value := EvalDateTime;
                end;

            FieldRef.Type::Option:
                begin
                    InStr.Read(EvalOption);
                    FieldRef.Value := EvalOption;
                end;

            FieldRef.Type::Guid:
                begin
                    InStr.Read(EvalGuid);
                    FieldRef.Value := EvalGuid;
                end;

            FieldRef.Type::Decimal:
                begin
                    InStr.Read(EvalDec);
                    FieldRef.Value := EvalDec;
                end;

            FieldRef.Type::Integer:
                begin
                    InStr.Read(EvalInt);
                    FieldRef.Value := EvalInt;
                end;

            FieldRef.Type::BigInteger:
                begin
                    InStr.Read(EvalBigInt);
                    FieldRef.Value := EvalBigInt;
                end;

            // Unknown ???
            else begin
                InStr.Read(TextData);
                FieldRef.Value := TextData;
            end;
        end;
    end;
    #endregion

    #region PermissionsSets

    procedure ExportTenantPermissionSetsGzip(var TempBlob: Codeunit "Temp Blob")
    var
        Compress: Codeunit "Data Compression";
        TempBlobUncompressed: Codeunit "Temp Blob";
        InStream: InStream;
        OutStream: OutStream;
        ExportPermissionSetsTenant: XmlPort "Export Permission Sets Tenant";
    begin
        TempBlobUncompressed.CreateOutStream(OutStream);
        ExportPermissionSetsTenant.SetExportToExtensionSchema(true);
        ExportPermissionSetsTenant.SetDestination(OutStream);
        ExportPermissionSetsTenant.Export();
        TempBlobUncompressed.CreateInStream(InStream);
        TempBlob.CreateOutStream(OutStream);
        Compress.GZipCompress(InStream, OutStream);
    end;

    procedure ImportTenantPermissionSetsGzip(var InStream: InStream)
    var
        Compress: Codeunit "Data Compression";
        TempBlobUncompressed: Codeunit "Temp Blob";
        OutStream: OutStream;
        ImportPermissionSets: XmlPort "Import Permission Sets";
    begin
        if Compress.IsGZip(InStream) then begin
            TempBlobUncompressed.CreateOutStream(OutStream);
            Compress.GZipDecompress(InStream, OutStream);
            TempBlobUncompressed.CreateInStream(InStream);
        end;
        ImportPermissionSets.SetSource(InStream);
        ImportPermissionSets.SetUpdatePermissions(true);
        ImportPermissionSets.Import();
    end;

    #endregion


    local procedure AutoMapOptionToBCField(var BCField: FieldRef; ValueToMap: Text; var MappedValue: Integer): Boolean
    var
        i: Integer;
        OptionCaptions: List of [Text];
    begin
        // Try to Auto-Map regarding the label :
        OptionCaptions := BCField.OptionMembers.Split(',');
        i := 1;
        if BCField.EnumValueCount() > 0 then // this work both for option and enum
            repeat
                // Caption
                if (BCField.GetEnumValueCaption(i) = ValueToMap)
                or (OptionCaptions.Get(i) = ValueToMap) then begin
                    MappedValue := BCField.GetEnumValueOrdinal(i);
                    exit(true);
                end;
                i += 1;
            until i > BCField.EnumValueCount();
    end;

    local procedure ParseISODuration(IsoDuration: Text): Duration
    var
        Hours, Minutes, Seconds : Integer;
        TimePart: Text;
    begin
        // Example input: 'P0DT12H0M0.0S'
        // Extract the time part after the 'T'
        if StrPos(IsoDuration, 'T') > 0 then
            TimePart := CopyStr(IsoDuration, StrPos(IsoDuration, 'T') + 1)
        else
            exit(0); // No time part found

        // Parse hours
        if StrPos(TimePart, 'H') > 0 then
            Evaluate(Hours, CopyStr(TimePart, 1, StrPos(TimePart, 'H') - 1));

        // Parse minutes
        if StrPos(TimePart, 'M') > 0 then
            Evaluate(Minutes, CopyStr(TimePart, StrPos(TimePart, 'H') + 1, StrPos(TimePart, 'M') - StrPos(TimePart, 'H') - 1));

        // Parse seconds (might be decimal)
        if StrPos(TimePart, 'S') > 0 then
            Evaluate(Seconds, CopyStr(TimePart, StrPos(TimePart, 'M') + 1, StrPos(TimePart, 'S') - StrPos(TimePart, 'M') - 1));

        // Convert to Duration
        exit(Hours * 3600000 + Minutes * 60000 + Seconds * 1000);
    end;

    local procedure Min(Val1: BigInteger; Val2: BigInteger): BigInteger
    begin
        if Val1 > Val2 then
            exit(Val2)
        else
            exit(Val1);
    end;

    /*
        Keep variable as Global scope to reduce memory allocation operations
        This codeunit is intensively called (per field) therefore declaring them in local have poor performance
    */
    var
        ClassifiedDataHandling: Option "Keep","Empty","Randomize";
        BlobMgt: Codeunit "TOO Pipou Blob Mgt.";
        Logentry: Integer;
        CR: Text[1];
        LF: Text[1];
        Initialized: Boolean;
        TextData: Text;
        EvalBigInt: BigInteger;
        LowInt: Integer;
        EvalInt: Integer;
        EvalOption: Option;
        EvalDec: Decimal;
        EvalDuration: Duration;
        EvalDate: Date;
        EvalDateTime: DateTime;
        EvalGuid: Guid;
        EvalDecimal: Decimal;
        EvalTime: Time;
        EvalBool: Boolean;
        EvalRecID: RecordId;
        EvalDateFormula: DateFormula;
        BlobMaxSize: Integer;
        EmptyGuid: Guid;
        EmptyRecID: RecordId;
        EmptyDateformula: DateFormula;
        EmptyDecimal: Decimal;
        EmptyDate: Date;
        EmptyTime: Time;
        EmptyDateTime: DateTime;
        EvalByte: Byte;
        OneByte: Byte;
        ZeroByte: Byte;
        AllALTypes: RecordRef;
        DefTextFieldRef, DefCodeFieldRef, DefIntFieldRef, DefBigIntFieldRef, DefDecFieldRef, DefDurFieldRef, DefDateFieldRef, DefDateTimeFieldRef, DefTimeFieldRef, DefRecIDFieldRef, DefDateFormulaFieldRef : FieldRef;
}