codeunit 51009 "TOO Pipou Import Data"
{
    // multi thread data import from pipou archive
    TableNo = "TOO Pipou Thread";

    #region OnRun
    trigger OnRun()
    var
        Archive: Record "TOO Pipou Archive";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        ArchiveFile: Record "TOO Pipou Archive Files";
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
            // Set as imported
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
    local procedure ImportTableData(var Thread: Record "TOO Pipou Thread"; var Archive: Record "TOO Pipou Archive"; var ArchiveFile: Record "TOO Pipou Archive Files"; VAR Table: Record "TOO Pipou Archive Tables")
    var
        CompressedInstr: InStream;
        TempBlob: Codeunit "Temp Blob";
        OutStream: OutStream;
        DataInStream: InStream;
        FieldInDataCount: Integer;
        FieldMatchedCount: Integer;
        RecordRef: RecordRef;
        Fields: Record Field;
        TableMeta: Record "Table Metadata";
        FieldsOriginalIDList: array[500] of Integer;
        FieldsOriginalTypeList: array[500] of Integer;
        FieldsOriginalMatchedIndex: array[500] of Integer;
        FieldsMatchedID: array[500] of Integer;
        FieldsMatchedOriginalIndex: array[500] of Integer;
        FieldsMatchedColumnEmpty: array[500] of Boolean;
        FieldsOriginalColumnEmpty: array[500] of Boolean;
        FieldsMatchedPartOfPK: array[500] of Boolean;
        FieldsMatchedTypes: array[500] of enum "TOO Fields Types";
        FieldsMatchedLen: array[500] of Integer;
        BCField: FieldRef;
        EmptyRecID: RecordId;
        I: Integer;
        ArchiveFields: Record "TOO Pipou Archive Fields";
        ArchiveTable: Record "TOO Pipou Archive Tables";
        CalulatedHash: Text;
        Hash: Codeunit "Cryptography Management";
        HashAlgorithmType: Option MD5,SHA1,SHA256,SHA384,SHA512;
        FileRecordPosition: Integer;
        RecorsNbUnChecked: Integer;
        UseSQL: Boolean;
        PkFieldsMapped: Integer;
        DataHasSystemAuditFields: Boolean;
        LocalNbRecs: Integer;
        LocalUserSecId: Guid;
        OrigFlatType: array[500] of Enum "TOO Fields Types";
        OrigFlatLen: array[500] of Integer;
        OrigFlatID: array[500] of Integer;
        CleanedErr: Text;
        LockedArchiveFile: Record "TOO Pipou Archive Files"; // used for row-level locking on Modify (BC 23 has no tristate locking)
    begin
        // Skip retention setup tables throwing errors
        if (ArchiveFile."Table ID" In [Database::"Retention Policy Setup", Database::"Retention Period", Database::"Retention Policy Setup Line", 3903, 9008, 8903])
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
            if (ArchiveFields."Matched Field ID" > 0) then begin
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
            end;
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

            if not PipouMgt.TryClearTableContent(RecordRef) then begin
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

        #region SQL columns
#if ONPREM
        // Prepare SQL Bulk
        if (Archive."Import Use SQL Bulk") then begin
            // Only use sql bulk with bin format
            UseSQL := true;
            SQLHelper.Open(ArchiveFile."Matched Table ID", Archive."Import Destination Company");
            RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
            for I := 1 to FieldMatchedCount do
                // Add all matched fields + force PK even if it is empty
                if not FieldsMatchedColumnEmpty[I] or FieldsMatchedPartOfPK[I] or (FieldsMatchedID[I] > 2000000000) then
                    SQLHelper.AddBulkColumn(RecordRef.Field(FieldsMatchedID[I]), FieldsMatchedPartOfPK[I]);
            // Also Add audit fields
            if not DataHasSystemAuditFields then
                SQLHelper.AddBulkColumnAudits();
        end else
            // Just open recref for AL
            RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
#else
        // Just open recref for AL
        RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
#endif
        #endregion

        // Prepare columns streams
        if ArchiveFile."Column Storage" then
            for I := 1 to FieldMatchedCount do
                if not FieldsMatchedColumnEmpty[I] then
                    ColStoreMgt.GetOriginalfieldIDColumnInStr(FieldsOriginalIDList[FieldsMatchedOriginalIndex[i]], MatchedDataColInStream[I]);

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
                                SQLHelper.AddBulkValueFromBin(FieldsMatchedTypes[I], FieldsMatchedLen[I], MatchedDataColInStream[I])
                            else
                                // Still pass default value for PK, even if empty (SQL bulk insert throw error if PK is null)
                                if FieldsMatchedPartOfPK[I] then
                                    SQLHelper.AddBulkRowValue(RecordRef.Field(FieldsMatchedID[I]), true);
                        if not DataHasSystemAuditFields then
                            SQLHelper.AddBulkRowValueAudit(CurrentDateTime, LocalUserSecId, CurrentDateTime, LocalUserSecId);
                        SQLHelper.Insert();
                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end
                else
                    // Row oriented
                    while (not DataInStream.EOS and (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs)) do begin
                        for I := 1 to FieldInDataCount do
                            if (FieldsOriginalMatchedIndex[I] = 0) then
                                PipouMgt.SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream)
                            else if FieldsOriginalColumnEmpty[I] then begin
                                PipouMgt.SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream);
                                if FieldsMatchedPartOfPK[I] then
                                    SQLHelper.AddBulkRowValue(RecordRef.Field(OrigFlatID[I]), true);
                            end else
                                SQLHelper.AddBulkValueFromBin(OrigFlatType[I], OrigFlatLen[I], DataInStream);
                        if not DataHasSystemAuditFields then
                            SQLHelper.AddBulkRowValueAudit(CurrentDateTime, LocalUserSecId, CurrentDateTime, LocalUserSecId);
                        SQLHelper.Insert();
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
                                if not PipouMgt.EvaluateBinaryToBCField(BCField, MatchedDataColInStream[I]) then
                                    PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, RecordRef.RecordId, StrSubstNo('Unable to parse value into field %1, stream position %2 : %3', BCField.Caption, DataInStream.Position, GetLastErrorText));
                            end;
                        if not PipouMgt.TryInsertRecRef(RecordRef) then
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
                                PipouMgt.SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream)
                            else if FieldsOriginalColumnEmpty[I] then
                                PipouMgt.SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream)
                            else begin
                                BCField := RecordRef.Field(OrigFlatID[I]);
                                if not PipouMgt.EvaluateBinaryToBCField(BCField, DataInStream) then
                                    PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, RecordRef.RecordId, StrSubstNo('Unable to parse value into field %1, stream position %2', BCField.Caption, DataInStream.Position));
                            end;
                        if not PipouMgt.TryInsertRecRef(RecordRef) then
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
            if SQLHelper.CommitBulkInserts() then begin
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



    var
        TotalProceedRec: Integer;
        LastThreadUpdateDT: DateTime;
        StartDT: DateTime;
        PipouMgt: Codeunit "TOO Pipou Mgt.";
        ColStoreMgt: Codeunit "TOO Pipou colstore Mgt.";
        ThreadHelper: Codeunit "TOO Pipou Threads Mgt.";
        AdvCompress: Codeunit "TOO Advanced Compression Mgt.";
        // Options :
        IgnoreContatcBusRelation: Boolean;
        IgnoreArchives: Boolean;
        IgnoreLogsNBuffers: Boolean;
        MatchedDataColInStream: Array[500] of InStream;
        EmptyGuid: Guid;
#if ONPREM
        SQLHelper: Codeunit "TOO SQL Helper Bulk Insert";
#endif
}