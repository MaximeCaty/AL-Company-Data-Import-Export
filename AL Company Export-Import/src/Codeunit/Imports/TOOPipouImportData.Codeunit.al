codeunit 51009 "TOO Pipou Import Data"
{
    // multi thread data import from pipou archive
    TableNo = "TOO Pipou Thread";

    #region OnRun
    trigger OnRun()
    var
        Archive: Record "TOO Pipou Archive";
        ArchiveFile: Record "TOO Pipou Archive Files";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        OtherThreads: Record "TOO Pipou Thread";
        IgnoreEvents: Codeunit "TOO Pipou Import Events";
    begin
        // Set thread status as started
        Rec."Session ID" := SessionId();
        Rec.Status := Rec.Status::"Importing Data";
        Rec.Modify();
        Commit();

        // Table range to proceed
        ArchiveFile.SetAutoCalcFields("Matched Table ID");
        ArchiveFile.SetRange("Archive ID", Rec."Archive ID");
        ArchiveFile.SetRange("Affected Thread", Rec."Thread No.");
        ArchiveFile.SetRange(Imported, false);

        Archive.Get(Rec."Archive Name", Rec."Archive ID");
        PipouMgt.Initialize(1024 * 1024 * 100, Archive.ClassifiedDataHandling); // 100 MB max blob import
        BindSubscription(IgnoreEvents);

        LastThreadUpdateDT := CurrentDateTime;
        // Loop Files to import
        if ArchiveFile.FindSet() then
            repeat
                ArchiveTables.ReadIsolation := ArchiveTables.ReadIsolation::ReadUncommitted;
                ArchiveTables.Get(ArchiveFile."Archive ID", ArchiveFile."Table ID");
                if not ImportTableData(Rec, Archive, ArchiveFile, ArchiveTables) then
                    PipouMgt.LogALErrorMessage(ArchiveFile, GetLastErrorText(), GetLastErrorCallStack());

            until ArchiveFile.Next() = 0;

        UnbindSubscription(IgnoreEvents);

        // All thread completed, update archive status + remove threads
        OtherThreads.SetRange("Archive ID", Archive."Archive ID");
        OtherThreads.SetFilter("Thread No.", '<>%1', Rec."Thread No.");
        OtherThreads.SetFilter(Status, '<>%1', OtherThreads.Status::"Completed ✅");
        if OtherThreads.IsEmpty() then begin
            Archive.Get(Archive."Archive Name", Archive."Archive ID");
            // Detect if fully or partialy imported
            ArchiveFile.SetRange("Archive ID", Rec."Archive ID");
            ArchiveFile.SetRange("Affected Thread", Rec."Thread No.");
            ArchiveFile.SetRange(Imported, false);
            if ArchiveFile.IsEmpty then
                Archive."Process Status" := Archive."Process Status"::"✅ Imported"
            else
                Archive."Process Status" := Archive."Process Status"::"✅ Partially Imported";
            Archive.Modify();
            if Archive."Import Use SQL Bulk" then
                SelectLatestVersion(); // clear instance cache to force SQL table re-read
            // Remove all threads later
            sleep(250);
            OtherThreads.Reset();
            OtherThreads.SetRange("Archive ID", Archive."Archive ID");
            OtherThreads.DeleteAll();
            Commit();
        end else begin
            // Mark thread as completed
            Rec.Status := Rec.Status::"Completed ✅";
            Rec.Modify();
            Commit();
        end;
    end;
    #endregion

    #region Import Table
    [TryFunction]
    local procedure ImportTableData(var Thread: Record "TOO Pipou Thread"; var Archive: Record "TOO Pipou Archive"; var ArchiveFile: Record "TOO Pipou Archive Files"; var Table: Record "TOO Pipou Archive Tables")
    var
        Fields: Record Field;
        ExtraField: Record Field;
        TableMeta: Record "Table Metadata";
        ArchiveFields: Record "TOO Pipou Archive Fields";
        LockedArchiveFile: Record "TOO Pipou Archive Files"; // used for row-level locking on Modify (BC 23 has no tristate locking)
        ArchiveTable: Record "TOO Pipou Archive Tables";
        Hash: Codeunit "Cryptography Management";
        TempBlob: Codeunit "Temp Blob";
        EmptyRecID: RecordId;
        RecordRef: RecordRef;
        BCField: FieldRef;
        DataHasSystemAuditFields: Boolean;
        FieldsMatchedColumnEmpty: array[500] of Boolean;
        FieldsMatchedPartOfPK: array[500] of Boolean;
        FieldsOriginalColumnEmpty: array[500] of Boolean;
        UseSQL: Boolean;
        FieldsMatchedTypes: array[500] of Enum "TOO Fields Types";
        OrigFlatType: array[500] of Enum "TOO Fields Types";
        LocalUserSecId: Guid;
        CompressedInstr: InStream;
        DataInStream: InStream;
        FieldInDataCount: Integer;
        FieldMatchedCount: Integer;
        FieldsMatchedID: array[500] of Integer;
        FieldsMatchedLen: array[500] of Integer;
        FieldsMatchedOriginalIndex: array[500] of Integer;
        FieldsOriginalIDList: array[500] of Integer;
        FieldsOriginalMatchedIndex: array[500] of Integer;
        FieldsOriginalTypeList: array[500] of Integer;
        FieldsExtraID: array[500] of Integer; // destination fields absent from the archive, filled with BC empty value
        FieldsExtraCount: Integer;
        MatchedIDs: List of [Integer];
        FileRecordPosition: Integer;
        I: Integer;
        LocalNbRecs: Integer;
        OrigFlatID: array[500] of Integer;
        OrigFlatLen: array[500] of Integer;
        PkFieldsMapped: Integer;
        RecorsNbUnChecked: Integer;
        HashAlgorithmType: Option MD5,SHA1,SHA256,SHA384,SHA512;
        OutStream: OutStream;
        CalulatedHash: Text;
        CleanedErr: Text;
    begin
        // Skip retention setup tables throwing errors
        if (ArchiveFile."Table ID" in [Database::"Retention Policy Setup", Database::"Retention Period", Database::"Retention Policy Setup Line", 3903, 9008, 8903])
        and not (Archive."Import Use SQL Bulk") then
            exit;

        // Skip contatc business relation if disabled
        if IgnoreContatcBusRelation and (ArchiveFile."Table ID" = Database::"Contact Business Relation") then
            exit;

        // Skip *Archive tables if disabled
        if IgnoreArchives and ((ArchiveFile."Table Name".EndsWith(' Archive')) or (ArchiveFile."Table ID" = 1900)) then
            exit;

        // Skip *Log tables if disabled
        if IgnoreLogsNBuffers and (ArchiveFile."Table Name".Contains(' Buffer') or ArchiveFile."Table Name".EndsWith(' Log')) then
            exit;

        #region Check Table
        if not TableMeta.Get(ArchiveFile."Matched Table ID") then begin
            if ArchiveFile."Chunk No." = 1 then // log only first attempt
                PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, EmptyRecID, StrSubstNo('Unable to find Table ID  %1 : "%2" ', TableMeta.Name, ArchiveFile."Table Name"));
            // Row-level lock: re-get by PK so SQL Server takes a row lock instead of a table/range lock (BC 23 has no tristate locking)
            LockedArchiveFile.LockTable();
            LockedArchiveFile.Get(ArchiveFile."Archive Name", ArchiveFile."Archive ID", ArchiveFile."File Name");
            LockedArchiveFile.Modify();
            exit;
        end;
        #endregion

        #region Fields Def.
        // Read fields definition
        FieldMatchedCount := 0;
        I := 1;
        ArchiveFields.SetRange("Archive ID", Archive."Archive ID");
        ArchiveFields.SetRange("Table ID", ArchiveFile."Table ID");
        ArchiveFields.FindSet();
        repeat
            FieldsOriginalIDList[I] := ArchiveFields."Field ID";
            FieldsOriginalTypeList[I] := ArchiveFields."Field Type";
            FieldsOriginalColumnEmpty[I] := ArchiveFields."Empty In Chunks List".Contains(Format(Archivefile."Chunk No."));
            FieldsOriginalMatchedIndex[I] := 0;
            FieldInDataCount += 1;
            // Load matched field to import
            if (ArchiveFields."Matched Field ID" > 0) then
                if Fields.Get(ArchiveFile."Matched Table ID", ArchiveFields."Matched Field ID") then begin
                    // Ignore system fields for AL import
                    if Archive."Import Use SQL Bulk" or (Fields."No." < 2000000000) then
                        // Ignore empty column for column oriented file, unless PK
                        if (not FieldsOriginalColumnEmpty[I]) or (not ArchiveFile."Column Storage") or Fields.IsPartOfPrimaryKey then begin
                            FieldMatchedCount += 1;
                            FieldsOriginalMatchedIndex[I] := FieldMatchedCount;
                            FieldsMatchedID[FieldMatchedCount] := Fields."No.";
                            FieldsMatchedOriginalIndex[FieldMatchedCount] := I;
                            FieldsMatchedColumnEmpty[FieldMatchedCount] := FieldsOriginalColumnEmpty[I];
                            FieldsMatchedPartOfPK[FieldMatchedCount] := Fields.IsPartOfPrimaryKey;
                            if Fields.IsPartOfPrimaryKey then
                                PkFieldsMapped += 1;
                            FieldsMatchedTypes[FieldMatchedCount] := Fields.Type;
                            FieldsMatchedLen[FieldMatchedCount] := Fields.Len;
                            if Fields."No." > 2000000000 then
                                DataHasSystemAuditFields := true;
                        end;
                end else
                    // Handle missing field
                    if ArchiveFile."Chunk No." = 1 then
                        PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, EmptyRecID, StrSubstNo('Unable to match field in Table "%1" :\ Name : %2\ Caption : %3 \ID : %4 \Type : %5', TableMeta.Name, ArchiveFields."Field Name", ArchiveFields."Field Caption", ArchiveFields."Field ID", ArchiveFields."Field Type Name"));
            I += 1;
        until ArchiveFields.Next() = 0;

        // Fields matching
        if FieldInDataCount = 0 then
            Error('Data corrupted in %1 : Field definition empty or corrupted.', ArchiveFile."File Name");
        if FieldMatchedCount = 0 then
            Error('Unable to match any field from the imported data dedinition in Table "%1".', TableMeta.Name);
        // PK is mapped
        Fields.SetRange(TableNo, ArchiveFile."Matched Table ID");
        Fields.SetRange("No.");
        Fields.SetRange(IsPartOfPrimaryKey, true);
        if Fields.Count() <> PkFieldsMapped then
            Error('Primary key not mapped or partialy mapped for Table "%1". Primary key must be mapped to import datas.', TableMeta.Name);

        // Pre-cache hot path values
        LocalNbRecs := ArchiveFile."Number Of Recs";
        LocalUserSecId := UserSecurityId();
        for I := 1 to FieldInDataCount do
            if FieldsOriginalMatchedIndex[I] > 0 then begin
                OrigFlatType[I] := FieldsMatchedTypes[FieldsOriginalMatchedIndex[I]];
                OrigFlatLen[I] := FieldsMatchedLen[FieldsOriginalMatchedIndex[I]];
                OrigFlatID[I] := FieldsMatchedID[FieldsOriginalMatchedIndex[I]];
            end;
        #endregion

        #region Truncate
        // Clear tables data
        ArchiveTable.LockTable();
        ArchiveTable.Get(Archive."Archive ID", ArchiveFile."Table ID");
        if Archive.DeleteData and not ArchiveTable."PreImport Truncated" then begin
            RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");

            // Update thread status
            Thread."Current Table" := Table."Table Name";
            Thread."Current File" := ArchiveFile."File Name";
            Thread."Current File Progress %" := 0;
            Thread."Total Rec. Proceed" := TotalProceedRec;
            Thread.Status := Thread.Status::"Truncating Table";
            Thread.Modify();
            Commit();

            if not TryClearTableContent(RecordRef) then begin
                PipouMgt.LogClearTableErrorMessage(ArchiveFile, GetLastErrorText());
                ClearLastError();
                exit;
            end else begin
                ArchiveTable.Get(Archive."Archive ID", ArchiveFile."Table ID");
                if not ArchiveTable."PreImport Truncated" then begin // in case two thread were truncating at same time
                    ArchiveTable."PreImport Truncated" := true;
                    ArchiveTable.Modify();
                end;
                Commit();
            end;
            Clear(RecordRef);
        end;
        #endregion

        #region Decompress
        // Decompress data

        // Update thread status
        Thread."Current Table" := Table."Table Name";
        Thread."Current File" := ArchiveFile."File Name";
        Thread."Current File Progress %" := 0;
        Thread."Total Rec. Proceed" := TotalProceedRec;
        Thread.Status := Thread.Status::"Decompressing - Decoding";
        Thread.Modify();
        Commit();

        ArchiveFile.CalcFields(Data);

        if ArchiveFile."Column Storage" then begin
            // COLUMN ORIENTED
            // Extract columns data from the file separatly
            ColStoreMgt.OpenColStore(ArchiveFile);
            ColStoreMgt.GetColumnInStr(1, DataInStream); // for first EOS loop check
        end else begin
            // ROW ORIENTED (with record separator, field written in same order than metadata)
            ArchiveFile.Data.CreateInStream(CompressedInstr);
            TempBlob.CreateOutStream(OutStream);
            AdvCompress.Decompress(CompressedInstr, OutStream, ArchiveFile."Compression Mode");
            TempBlob.CreateInStream(DataInStream);
            if DataInStream.Length < 1 then
                Error('File "%1" : Data corrupted, decompression failed or empty file. Stream length : %2', ArchiveFile."File Name", DataInStream.Length);

            // Decompression Signature integrity check
            if ArchiveFile."Uncompressed MD5 Hash" <> '' then begin
                CalulatedHash := Hash.GenerateHash(DataInStream, HashAlgorithmType::MD5);
                if ArchiveFile."Uncompressed MD5 Hash" <> CalulatedHash then
                    Error('File "%1" decompression integrity check failed.\Original data signature hash : %1\Decompressed data signature hash : %2', ArchiveFile."File Name", ArchiveFile."Uncompressed MD5 Hash", CalulatedHash);
                DataInStream.ResetPosition();
            end;
        end;
        clear(CompressedInstr); // free ram from original compressed stream
        #endregion

        // Prepare columns streams
        if ArchiveFile."Column Storage" then
            for I := 1 to FieldMatchedCount do
                if not FieldsMatchedColumnEmpty[I] then
                    if not ColStoreMgt.GetOriginalfieldIDColumnInStr(FieldsOriginalIDList[FieldsMatchedOriginalIndex[i]], MatchedDataColInStream[I]) then
                        FieldsMatchedColumnEmpty[I] := true; // column not found

        #region SQL columns
#if ONPREM
        // Prepare SQL Bulk
        if (Archive."Import Use SQL Bulk") then begin
            // Only use sql bulk with bin format
            UseSQL := true;
            SQLOpen(ArchiveFile."Matched Table ID", Archive."Import Destination Company");
            RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
            // BC SQL columns are NOT NULL and have no DEFAULT constraint : every column left out of the bulk
            // insert would be sent as NULL. So map all matched fields, empty ones get the BC empty value.
            for I := 1 to FieldMatchedCount do begin
                SQLAddBulkColumn(RecordRef.Field(FieldsMatchedID[I]), FieldsMatchedPartOfPK[I]);
                MatchedIDs.Add(FieldsMatchedID[I]);
            end;

            // Same reason : destination fields that do not exist in the archive at all
            FieldsExtraCount := 0;
            ExtraField.SetRange(TableNo, ArchiveFile."Matched Table ID");
            ExtraField.SetRange(Class, ExtraField.Class::Normal);
            ExtraField.SetFilter("No.", '<%1', 2000000000); // system fields are handled by the audit columns
            ExtraField.SetFilter(ObsoleteState, '<>%1', ExtraField.ObsoleteState::Removed); // removed fields have no SQL column
            if ExtraField.FindSet() then
                repeat
                    // TableFilter has no SQL type mapping in SQLAddBulkColumn (BC runtime dll type), map it there if such a field ever fails
                    if not MatchedIDs.Contains(ExtraField."No.")
                    and (ExtraField.Type <> ExtraField.Type::TableFilter) then begin
                        FieldsExtraCount += 1;
                        FieldsExtraID[FieldsExtraCount] := ExtraField."No.";
                        SQLAddBulkColumn(RecordRef.Field(ExtraField."No."), false);
                    end;
                until ExtraField.Next() = 0;

            // Also Add audit fields
            if not DataHasSystemAuditFields then
                SQLAddBulkColumnAudits();
        end else
            // Just open recref for AL
            RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
#else
        // Just open recref for AL
        RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
#endif
        #endregion

        #region Parse Records
        Thread.Status := Thread.Status::"Importing Data";
        Thread.Modify();
        Commit();
        case UseSQL of
#if ONPREM
            true:
                #region SQL
                if ArchiveFile."Column Storage" then
                    // Column oriented
                    while (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs) do begin
                        for I := 1 to FieldMatchedCount do
                            // Ignore empty column : not exported
                            if not FieldsMatchedColumnEmpty[I] then
                                SQLAddBulkValueFromBin(FieldsMatchedTypes[I], FieldsMatchedLen[I], MatchedDataColInStream[I])
                            else
                                // Column not exported : still pass BC empty value (SQL columns are NOT NULL)
                                SQLAddBulkRowEmptyValue(RecordRef.Field(FieldsMatchedID[I]));
                        SQLAddBulkRowExtraEmptyValues(RecordRef, FieldsExtraID, FieldsExtraCount);
                        if not DataHasSystemAuditFields then
                            SQLAddBulkRowValueAudit(CurrentDateTime, LocalUserSecId, CurrentDateTime, LocalUserSecId);
                        SQLInsert();
                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end
                else
                    // Row oriented
                    while (not DataInStream.EOS and (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs)) do begin
                        for I := 1 to FieldInDataCount do
                            if (FieldsOriginalMatchedIndex[I] = 0) then
                                SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream)
                            else if FieldsOriginalColumnEmpty[I] then begin
                                SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream);
                                // Column not exported : still pass BC empty value (SQL columns are NOT NULL)
                                SQLAddBulkRowEmptyValue(RecordRef.Field(OrigFlatID[I]));
                            end else
                                SQLAddBulkValueFromBin(OrigFlatType[I], OrigFlatLen[I], DataInStream);
                        SQLAddBulkRowExtraEmptyValues(RecordRef, FieldsExtraID, FieldsExtraCount);
                        if not DataHasSystemAuditFields then
                            SQLAddBulkRowValueAudit(CurrentDateTime, LocalUserSecId, CurrentDateTime, LocalUserSecId);
                        SQLInsert();
                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end;
            #endregion
#endif
            false:
                #region AL
                if ArchiveFile."Column Storage" then
                    // Column oriented
                    while (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs) do begin
                        for I := 1 to FieldMatchedCount do
                            if not FieldsMatchedColumnEmpty[I] then begin
                                BCField := RecordRef.Field(FieldsMatchedID[I]);
                                if not EvaluateBinaryToBCField(BCField, MatchedDataColInStream[I]) then
                                    PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, RecordRef.RecordId, StrSubstNo('Unable to parse value into field %1, stream position %2 : %3', BCField.Caption, DataInStream.Position, GetLastErrorText));
                            end;
                        if not TryInsertRecRef(RecordRef) then
                            PipouMgt.LogInsertRecErrorMessage(ArchiveFile, RecordRef.RecordId, GetLastErrorText());
                        Clear(RecordRef);
                        RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end
                else
                    // Row oriented
                    while (not DataInStream.EOS and (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs)) do begin
                        for I := 1 to FieldInDataCount do
                            if (FieldsOriginalMatchedIndex[I] = 0) then
                                SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream)
                            else if FieldsOriginalColumnEmpty[I] then
                                SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream)
                            else begin
                                BCField := RecordRef.Field(OrigFlatID[I]);
                                if not EvaluateBinaryToBCField(BCField, DataInStream) then
                                    PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, RecordRef.RecordId, StrSubstNo('Unable to parse value into field %1, stream position %2', BCField.Caption, DataInStream.Position));
                            end;
                        if not TryInsertRecRef(RecordRef) then
                            PipouMgt.LogInsertRecErrorMessage(ArchiveFile, RecordRef.RecordId, GetLastErrorText());
                        Clear(RecordRef);
                        RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end;
        #endregion
        end;

        FileRecordPosition += RecorsNbUnChecked;
        TotalProceedRec += RecorsNbUnChecked;
        #endregion

        // Free RAM
        RecordRef.Close();
        if ArchiveFile."Column Storage" then
            clear(ColStoreMgt); // free memory from column datas

        #region Commit
        // Thread Status
        Thread."Current File Progress %" := 100;
        Thread."Total Rec. Proceed" := TotalProceedRec;
        Thread.Status := Thread.Status::Commiting;
        Thread.Modify();
        Commit();

        // Commit
        if UseSQL then begin
#if ONPREM
            ClearLastError();
            // Table lock only when a single thread feeds this table; per-row locks when several do (allows concurrent bulk insert)
            if SQLCommitBulkInserts(not TableImportedByMultipleThreads(ArchiveFile)) then begin
                SelectLatestVersion(ArchiveFile."Table ID");
                // LockTable + Get by PK = row-level UPDLOCK, avoids table/range lock for BC < 23 (before tri-state lock versions)
                LockedArchiveFile.LockTable(true);
                LockedArchiveFile.Get(ArchiveFile."Archive Name", ArchiveFile."Archive ID", ArchiveFile."File Name");
                LockedArchiveFile.Imported := true;
                LockedArchiveFile.Modify(false);
                Commit();
            end else begin
                // Compact DotNet error :
                CleanedErr := GetLastErrorText();
                if CleanedErr.IndexOf(' : ') > 0 then
                    CleanedErr := CopyStr(CleanedErr, CleanedErr.IndexOf(' : ') + 3);
                if CleanedErr.IndexOf('Error: ') > 0 then
                    CleanedErr := CopyStr(CleanedErr, CleanedErr.IndexOf('Error: ') + 7);
                PipouMgt.LogCommitErrorMessage(ArchiveFile, CleanedErr);
            end;
#endif
        end else begin
            ClearLastError();
            if TryCommit() then begin
                // LockTable + Get by PK = row-level UPDLOCK, avoids table/range lock for BC < 23 (before tri-state lock versions)
                LockedArchiveFile.LockTable(true);
                LockedArchiveFile.Get(ArchiveFile."Archive Name", ArchiveFile."Archive ID", ArchiveFile."File Name");
                LockedArchiveFile.Imported := true;
                LockedArchiveFile.Modify(false);
                Commit();
            end else
                PipouMgt.LogCommitErrorMessage(ArchiveFile, GetLastErrorText());
        end;
        #endregion
    end;

    [TryFunction]
    local procedure TryCommit()
    begin
        Commit();
    end;

    local procedure TableImportedByMultipleThreads(var ArchiveFile: Record "TOO Pipou Archive Files"): Boolean
    var
        OtherFiles: Record "TOO Pipou Archive Files";
    begin
        // Same table fed by files assigned to another thread → concurrent bulk insert into one SQL table
        OtherFiles.SetRange("Archive ID", ArchiveFile."Archive ID");
        OtherFiles.SetRange("Table ID", ArchiveFile."Table ID");
        OtherFiles.SetFilter("Affected Thread", '<>%1', ArchiveFile."Affected Thread");
        exit(not OtherFiles.IsEmpty());
    end;
    #endregion

    #region Misc
    local procedure UpdateImportProgress(var RecorsNbUnChecked: Integer; var FileRecordPosition: Integer; var Table: Record "TOO Pipou Archive Tables"; var ArchiveFile: Record "TOO Pipou Archive Files"; var Thread: Record "TOO Pipou Thread")
    begin
        FileRecordPosition += RecorsNbUnChecked;
        TotalProceedRec += RecorsNbUnChecked;
        RecorsNbUnChecked := 0;
        if CurrentDateTime - LastThreadUpdateDT > 1000 then begin
            UpdateThreadProgress(Thread, Table."Table Name", ArchiveFile."File Name", round(FileRecordPosition / ArchiveFile."Number Of Recs" * 100, 1, '<'), TotalProceedRec);
            LastThreadUpdateDT := CurrentDateTime;
        end;
    end;

    local procedure UpdateThreadProgress(var Thread: Record "TOO Pipou Thread"; CurrTableName: Text[30]; CurrFileName: Text[150]; CurrFileProgg: Integer; ProceedRecs: Integer)
    begin
        Thread.Status := Thread.Status::"Importing Data";
        Thread."Current Table" := CurrTableName;
        Thread."Current File" := CurrFileName;
        Thread."Current File Progress %" := CurrFileProgg;
        Thread."Total Rec. Proceed" := ProceedRecs;
        Thread.Modify();
        Commit();
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


    #region Skip Bytes
    [TryFunction]
    procedure SkipBinaryBytesBCField(FieldTypeAsInt: Integer; var InStr: InStream)
    var
        MediaCount: Integer;
        MediaI: Integer;
        Text: Text;
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

    local procedure Min(Val1: BigInteger; Val2: BigInteger): BigInteger
    begin
        if Val1 > Val2 then
            exit(Val2)
        else
            exit(Val1);
    end;

#if ONPREM
    #region SQLOpen
    procedure SQLOpen(OpenTableID: Integer; FromCompanyName: Text)
    var
        AllObj: Record AllObj;
        Fields: Record Field;
        PublishedApp: Record "Published Application";
        TableOriginalApp: Record "Published Application";
        SourceTableName: Text;
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
        SourceTableName := SQLEscapeChar(TableMeta.Name);
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

        SQLBeginRow(); // prepare first row
    end;
    #endregion

    #region Column
    procedure SQLAddBulkColumn(FieldRef: FieldRef; IsPartOfPK: Boolean)
    var
        IndexOfFieldExt: Integer;
        Type: Text;
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
            FieldRef.Type::DateFormula:
                Type := 'string';
            FieldRef.Type::RecordId:
                Type := 'varbinary'; // written as SQL binary by SQLAddBulkRecIDValueToSQLBin
        // TableFilter type is in BC runtime dll
        end;
        IndexOfFieldExt := ListOfFieldInTableExt.IndexOf(FieldRef.Number);
        if IndexOfFieldExt > 0 then begin
            SQLBulkmporterHelper.AddColumn(SQLEscapeChar(FieldRef.Name) + '$' + DELCHR(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}').Tolower(), Type, IsPartOfPK);
            ListOfSQLField.Add(SQLEscapeChar(FieldRef.Name) + '$' + DELCHR(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}').ToLower() + ' : ' + Type);
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
                    SQLBulkmporterHelper.AddColumn(SQLEscapeChar(FieldRef.Name), Type, IsPartOfPK);
            end;
            ListOfSQLField.Add(SQLEscapeChar(FieldRef.Name) + ' : ' + Type);
        end;
        NoColumns += 1;
    end;

    procedure SQLAddBulkColumnAudits()
    begin
        SQLBulkmporterHelper.AddColumn('$systemCreatedAt', 'DateTime');
        SQLBulkmporterHelper.AddColumn('$systemCreatedBy', 'GUID');
        SQLBulkmporterHelper.AddColumn('$systemModifiedAt', 'DateTime');
        SQLBulkmporterHelper.AddColumn('$systemModifiedBy', 'GUID');
    end;
    #endregion

    #region Add BIN Value
    local procedure SQLAddBulkBlobValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        TempBlob: Codeunit "Temp Blob";
        BlobBytes: DotNet Array; // System.Array
        MemoryStream: DotNet MemoryStream;
        DotNetType: DotNet Type; // System.Type
        BlobInStr: InStream;
        Length: Integer;
        OutStr: OutStream;
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

    local procedure SQLAddBulkMediaValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        Guid: Guid;
        VariantVal: Variant;
    begin
        BlobMgt.ImportMediaBinary(Guid, InStr);
        VariantVal := Guid;
        SQLBulkmporterHelper.AddRowValue(VariantVal, ColumnZeroBaseIndex);
    end;

    local procedure SQLAddBulkMediaSetValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        Guid: Guid;
        VariantVal: Variant;
    begin
        BlobMgt.ImportMediaSetBinary(Guid, InStr);
        VariantVal := Guid;
        SQLBulkmporterHelper.AddRowValue(VariantVal, ColumnZeroBaseIndex);
    end;

    local procedure SQLAddBulkRecIDValueToSQLBin(var RecID: RecordId)
    var
        TempBlob: Codeunit "Temp Blob";
        MemoryStream: DotNet MemoryStream;
        RecIDInStr: InStream;
        RecIDOutStr: OutStream;
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
        I: Integer;
        PK: KeyRef;
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
        Hi: Byte;
        Lo: Byte;
    begin
        // Value must be 0..65535
        Lo := Value mod 256;
        Hi := (Value div 256) mod 256;
        OutStr.Write(Lo);
        OutStr.Write(Hi);
    end;

    procedure SQLAddBulkValueFromBin(var FieldType: Enum "TOO Fields Types"; var FieldLen: Integer; var InStr: InStream)
    begin
        case FieldType of
            FieldType::BLOB:
                AddBulkBlobValueFromBin(InStr, RowColumns);
            FieldType::Media:
                AddBulkMediaValueFromBin(InStr, RowColumns);
            FieldType::MediaSet:
                SQLAddBulkMediaSetValueFromBin(InStr, RowColumns);

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
                    SQLAddBulkRecIDValueToSQLBin(EvalRecID);
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
                    else
                        // EvalDate = ClosingDate(EvalDate) only for closing dates → flag stored as 23:59:59 in SQL
                        SQLBulkmporterHelper.AddRowValueALDate(Date2DMY(EvalDate, 3), Date2DMY(EvalDate, 2), Date2DMY(EvalDate, 1), RowColumns, EvalDate = ClosingDate(EvalDate));
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
    procedure SQLAddBulkRowValue(FieldValue: FieldRef; IsPartOfPK: Boolean)
    var
        BigInt: BigInteger;
        Guid: Guid;
        VariantVal: Variant;
    begin
        // Trnasform specific value for SQL interop
        case FieldValue.Type of
            // SQL datetime storage from date, time and datetime, require convert to utc+manualy empty date
            FieldValue.Type::Date:
                begin
                    EvalDate := FieldValue.Value;
                    if EvalDate = 0D then
                        SQLBulkmporterHelper.AddRowValueALDate(0, 0, 0, RowColumns)
                    else
                        // EvalDate = ClosingDate(EvalDate) only for closing dates → flag stored as 23:59:59 in SQL
                        SQLBulkmporterHelper.AddRowValueALDate(Date2DMY(EvalDate, 3), Date2DMY(EvalDate, 2), Date2DMY(EvalDate, 1), RowColumns, EvalDate = ClosingDate(EvalDate));
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

    procedure SQLAddBulkRowEmptyValue(FieldValue: FieldRef)
    var
        BlobBytes: DotNet Array; // System.Array
        DotNetType: DotNet Type; // System.Type
    begin
        // BC SQL columns are NOT NULL : a column without exported value must still receive the BC empty value
        case FieldValue.Type of
            FieldValue.Type::Blob:
                begin
                    // Blob value cannot be read from a FieldRef, send an empty byte array
                    BlobBytes := BlobBytes.CreateInstance(DotNetType.GetType('System.Byte'), 0);
                    SQLBulkmporterHelper.AddRowValue(BlobBytes, RowColumns);
                    RowColumns += 1;
                end;
            FieldValue.Type::RecordId:
                begin
                    // RecordID is stored as SQL binary, a variant value would not be understood by the bulk insert
                    SQLAddBulkRecIDValueToSQLBin(EmptyRecID);
                    RowColumns += 1;
                end;
            else
                // Empty DateFormula, Guid, Text, numbers… go through the standard variant conversion
                SQLAddBulkRowValue(FieldValue, false);
        end;
    end;

    procedure SQLAddBulkRowExtraEmptyValues(var RecordRef: RecordRef; var FieldsExtraID: array[500] of Integer; FieldsExtraCount: Integer)
    var
        I: Integer;
    begin
        // Destination fields absent from the archive : RecordRef is never modified, so its fields hold BC empty values
        for I := 1 to FieldsExtraCount do
            SQLAddBulkRowEmptyValue(RecordRef.Field(FieldsExtraID[I]));
    end;
    #endregion

    #region Add BIN Value
    local procedure AddBulkBlobValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        TempBlob: Codeunit "Temp Blob";
        BlobBytes: DotNet Array; // System.Array
        MemoryStream: DotNet MemoryStream;
        DotNetType: DotNet Type; // System.Type
        BlobInStr: InStream;
        Length: Integer;
        OutStr: OutStream;
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
        Guid: Guid;
        VariantVal: Variant;
    begin
        BlogMgt.ImportMediaBinary(Guid, InStr);
        VariantVal := Guid;
        SQLBulkmporterHelper.AddRowValue(VariantVal, ColumnZeroBaseIndex);
    end;

    procedure SQLAddBulkRowValueAudit(CreatedAt: DateTime; CreatedBy: Guid; ModifiedAt: DateTime; ModifiedBy: Guid)
    begin
        // Zero based column for dotnet
        SQLBulkmporterHelper.AddRowValue(CreatedAt, RowColumns);
        SQLBulkmporterHelper.AddRowValue(CreatedBy, RowColumns + 1);
        SQLBulkmporterHelper.AddRowValue(ModifiedAt, RowColumns + 2);
        SQLBulkmporterHelper.AddRowValue(ModifiedBy, RowColumns + 3);
    end;

    #region Insert Row
    procedure SQLInsert()
    var
        ErrColMisMatch: Label 'The number of values passed is different than the column definition.';
    begin
        if (RowColumns <> NoColumns) then
            Error(ErrColMisMatch);
        SQLBulkmporterHelper.EndRow();
        RowOpened := false;
        RowColumns := 0;
        SQLBeginRow(); // prepare next row if any
    end;

    #region Send Bulk
    [TryFunction]
    procedure SQLCommitBulkInserts(UseTableLock: Boolean)
    begin
        // UseTableLock = false → per-row locks, lets several threads bulk-insert the same table at once
        SQLBulkmporterHelper.WriteToServer(GetSqlConnectionString(), BaseTableSQLName, UseTableLock);
    end;
    #endregion
    #endregion

    #region internal
    local procedure SQLBeginRow()
    begin
        if not RowOpened then begin
            SQLBulkmporterHelper.BeginRow();
            RowOpened := true;
            RowColumns := 0;
        end;
    end;

    local procedure SQLEscapeChar(InputName: Text) OutPut: Text
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
    #endregion
#endif



    var
        EvalInt: Integer;
        EvalByte, ZeroByte : Byte;
        TotalProceedRec: Integer;
        EvalGuid: Guid;
        TextData: Text;
        EvalRecID: RecordId;
        EvalDateFormula: DateFormula;
        EvalDuration: Duration;
        LastThreadUpdateDT: DateTime;
        EvalBigInt: BigInteger;
        EvalDec: Decimal;
        EvalOption: Option;
        EvalDateTime: DateTime;
        EvalDate: Date;
        EvalTime: Time;
        PipouMgt: Codeunit "TOO Pipou Mgt.";
        ColStoreMgt: Codeunit "TOO Pipou colstore Mgt.";
        AdvCompress: Codeunit "TOO Advanced Compression Mgt.";
        BlobMgt: Codeunit "TOO Pipou Blob Mgt.";
        // Options :
        IgnoreContatcBusRelation: Boolean;
        IgnoreArchives: Boolean;
        IgnoreLogsNBuffers: Boolean;
        MatchedDataColInStream: array[500] of InStream;
#if ONPREM
        TableMeta: Record "Table Metadata";
        RowOpened: Boolean;
        RowColumns, NoColumns : Integer;
        ConnectionString, SQLFilter, SQLSelect, BaseTableSQLName, ExtTableSQLName, TableCompanyName : Text;
        SQLBulkmporterHelper: DotNet TOOSQLBulkImporterExt;
        EmptyGuid: Guid;
        BlogMgt: Codeunit "TOO Pipou Blob Mgt.";
        ListOfFieldInTableExtAppID: List of [Guid];
        ListOfFieldInTableExt: List of [Integer];
        ListOfSQLField: List of [Text];
        EmptyRecID: RecordId;
        VariantVal: Variant;
        EvalDataText: Text;
    //SQLHelper: Codeunit "TOO SQL Helper Bulk Insert";
#endif
}
