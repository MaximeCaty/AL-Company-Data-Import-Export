codeunit 51004 "TOO Pipou Mgt."
{
    SingleInstance = true;

    procedure Initialize(SetBlobMaxSize: Integer; ClassifiedDataExportHandling: Option Keep,Empty,Randomize)
    begin
        CR[1] := 13;
        LF[1] := 10;
        OneByte := 1;
        BlobMaxSize := SetBlobMaxSize;
        ClassifiedDataHandling := ClassifiedDataExportHandling;
    end;

    procedure ArchiveFormatVersion(): Integer
    begin
        // 2 : may carry FK dictionaries, and "Use Dictionary" is stamped by the export with the encoding the column
        //     actually got, so the import reads it instead of replaying the export rules.
        // 0 : no dictionaries, and no version written on the archive at all.
        exit(2);
    end;

    procedure IsFieldAnonymized(var ArchiveField: Record "TOO Pipou Archive Fields"; ClassifiedHandling: Option Keep,Empty,Randomize): Boolean
    var
        DataClassifOption: Option CustomerContent,ToBeClassified,EndUserIdentifiableInformation,AccountData,EndUserPseudonymousIdentifiers,OrganizationIdentifiableInformation,SystemMetadata;
    begin
        // Columns the export empties instead of exporting. Shared by the export and the import : the export drops them
        // out of the dictionary group, so an import reaching a different verdict decodes a plain column as ordinals.
        // Tested in steps : AL evaluates both sides of an "and" whatever the first one says.
        if ClassifiedHandling = ClassifiedHandling::Keep then
            exit(false);
        if ArchiveField."Part of Primary Key" then
            exit(false);
        if not (ArchiveField."Field DataClassification" in
                [DataClassifOption::CustomerContent, DataClassifOption::EndUserIdentifiableInformation,
                 DataClassifOption::EndUserPseudonymousIdentifiers, DataClassifOption::OrganizationIdentifiableInformation]) then
            exit(false);
        exit(ArchiveField."Field Name".ToLower() in
            ['name', 'email', 'e-mail', 'mail', 'phone no.', 'fax no.', 'phone', 'mobile phone no.', 'mobile no.',
             'birthday', 'birth date', 'address', 'address 1', 'address 2', 'street', 'city', 'post code', 'country',
             'family', 'title', 'martial', 'zip', 'zip code']);
    end;

    procedure GetMajorBCVersion(): Integer
    var
        AppSysConstants: Codeunit "Application System Constants";
        DotPos: Integer;
        Major: Integer;
        VersionText: Text;
    begin
        VersionText := AppSysConstants.PlatformProductVersion();
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


    local procedure LogMessage(var Chunk: Record "TOO Pipou Archive Files"; RecID: RecordId; Status: Option; Action: Option; ErrMsg: Text; CallStack: Text)
    var
        Log: Record "TOO Pipou Import Log";
    begin
        Log.Init();
        Log."Archive Name" := Chunk."Archive Name";
        Log."Archive ID" := Chunk."Archive ID";
        Log."Thread No." := Chunk."Affected Thread";
        Log."Chunk Entry No." := Chunk."File Name";
        Log."Record ID" := RecID;
        Log.Status := Status;
        Log.Action := Action;
        Log.Message := CopyStr(ErrMsg, 1, 2048);
        Log.CallStack := CopyStr(CallStack, 1, 2048);
        Log."Table ID" := Chunk."Table ID";
        Log."Table Name" := Chunk."Table Name";
        Log.Insert(true);
    end;
    #endregion

    #region PermissionsSets

    procedure ExportTenantPermissionSetsGzip(var TempBlob: Codeunit "Temp Blob")
    var
        Compress: Codeunit "Data Compression";
        TempBlobUncompressed: Codeunit "Temp Blob";
        ExportPermissionSetsTenant: XmlPort "Export Permission Sets Tenant";
        InStream: InStream;
        OutStream: OutStream;
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
        ImportPermissionSets: XmlPort "Import Permission Sets";
        OutStream: OutStream;
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

    /*
        Keep variable as Global scope to reduce memory allocation operations
        This codeunit is intensively called (per field) therefore declaring them in local have poor performance
    */
    var
        OneByte: Byte;
        BlobMaxSize: Integer;
        ClassifiedDataHandling: Option Keep,Empty,Randomize;
        CR: Text[1];
        LF: Text[1];

}