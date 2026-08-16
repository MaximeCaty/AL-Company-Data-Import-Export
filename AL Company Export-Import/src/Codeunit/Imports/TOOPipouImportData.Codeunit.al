codeunit 51009 "TOO Pipou Import Data"
{

    // force permission on protected tables to write into
    Permissions = tabledata "Approval Entry" = rimd,
     tabledata "Bank Account Ledger Entry" = rimd,
     tabledata "Bank Account Statement Line" = rimd,
tabledata "Batch Processing Parameter" = rimd,
tabledata "Cancelled Document" = rmid,
     tabledata "Capacity Ledger Entry" = rimd,
tabledata "Change Log Entry" = rimd,
tabledata "Check Ledger Entry" = rimd,
tabledata "Cust. Ledger Entry" = rimd,
tabledata "Detailed Cust. Ledg. Entry" = rimd,
tabledata "Detailed Employee Ledger Entry" = rimd,
tabledata "Detailed Vendor Ledg. Entry" = rimd,
tabledata "Dimension Set Entry" = rimd,
tabledata "Dimension Set Tree Node" = rmid,
tabledata "Employee Ledger Entry" = rimd,
tabledata "FA Ledger Entry" = rimd,
tabledata "FA Register" = rimd,
tabledata "G/L Entry" = rimd,
     tabledata "G/L Entry - VAT Entry Link" = rimd,
tabledata "G/L Register" = rimd,
tabledata "Ins. Coverage Ledger Entry" = rimd,
     tabledata "Invt. Receipt Header" = rimd,
tabledata "Invt. Receipt Line" = rimd,
tabledata "Invt. Shipment Header" = rimd,
tabledata "Invt. Shipment Line" = rimd,
tabledata "Issued Fin. Charge Memo Header" = rimd,
tabledata "Issued Reminder Header" = rimd,
tabledata "Issued Reminder Line" = rimd,
tabledata "Item Application Entry" = rimd,
tabledata "Item Application Entry History" = rimd,
tabledata "Item Ledger Entry" = rimd,
tabledata "Item Register" = rimd,
tabledata "Job Ledger Entry" = rimd,
     tabledata "Job Register" = rimd,
tabledata "Maintenance Ledger Entry" = rimd,
     tabledata "Payable Employee Ledger Entry" = rimd,
tabledata "Payable Vendor Ledger Entry" = rimd,
tabledata "Phys. Inventory Ledger Entry" = rimd,
tabledata "Posted Approval Comment Line" = rmid,
tabledata "Posted Approval Entry" = rimd,
tabledata "Post Value Entry to G/L" = rimd,
tabledata "Pstd. Phys. Invt. Order Hdr" = rimd,
tabledata "Pstd. Phys. Invt. Order Line" = rimd,
     tabledata "Pstd. Phys. Invt. Record Hdr" = rimd,
tabledata "Pstd. Phys. Invt. Record Line" = rimd,
tabledata "Purch. Comment Line Archive" = rimd,
tabledata "Purch. Cr. Memo Hdr." = rimd,
tabledata "Purch. Cr. Memo Line" = rimd,
     tabledata "Purch. Inv. Header" = rimd,
tabledata "Purch. Inv. Line" = rimd,
tabledata "Purch. Rcpt. Header" = rimd,
tabledata "Purch. Rcpt. Line" = rimd,
     tabledata "Purchase Header Archive" = rimd,
tabledata "Purchase Line Archive" = rimd,
tabledata "Reminder/Fin. Charge Entry" = rmid,
     tabledata "Res. Ledger Entry" = rimd,
tabledata "Return Receipt Header" = rimd,
tabledata "Return Receipt Line" = rimd,
     tabledata "Return Shipment Header" = rimd,
tabledata "Return Shipment Line" = rimd,
     tabledata "Sales Comment Line Archive" = rimd,
     tabledata "Sales Cr.Memo Header" = rimd,
tabledata "Sales Cr.Memo Line" = rimd,
tabledata "Sales Header Archive" = rimd,
     tabledata "Sales Invoice Header" = rimd,
tabledata "Sales Invoice Line" = rimd,
tabledata "Sales Line Archive" = rimd,
tabledata "Sales Shipment Header" = rimd,
tabledata "Sales Shipment Line" = rimd,
tabledata "Service Cr.Memo Header" = rimd,
     tabledata "Service Invoice Header" = rimd,
tabledata "Service Ledger Entry" = rimd,
     tabledata "Value Entry" = rimd,
tabledata "VAT Entry" = rimd,
tabledata "Vendor Ledger Entry" = rimd,
tabledata "Warehouse Entry" = rimd,
tabledata "Warranty Ledger Entry" = rimd,
tabledata "Workflow Record Change Archive" = rimd,
tabledata "Workflow Step Argument Archive" = rimd,
     tabledata "Workflow Step Instance Archive" = rimd;
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
                IgnoreEvents.SetCurrentTableNo(ArchiveFile."Table ID");
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
            if Archive."Process Started At" <> 0DT then
                Archive."Import Duration" := CurrentDateTime - Archive."Process Started At";
            Archive.Modify();
            if Archive."Import Use SQL Bulk" then
                SelectLatestVersion(); // clear instance cache to force SQL table re-read
            // Remove all threads later
            Sleep(250);
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
        TableMeta: Record "Table Metadata";
        ArchiveFields: Record "TOO Pipou Archive Fields";
        LockedArchiveFile: Record "TOO Pipou Archive Files"; // used for row-level locking on Modify (BC 23 has no tristate locking)
        ArchiveTable: Record "TOO Pipou Archive Tables";
        Hash: Codeunit "Cryptography Management";
        TempBlob: Codeunit "Temp Blob";
        EmptyRecID: RecordId;
        RecordRef: RecordRef;
        MatchedFieldRef: array[500] of FieldRef; // FieldRef per matched column, valid for the whole chunk : one record buffer reused
        OrigFlatFieldRef: array[500] of FieldRef; // same, indexed by original (archive) field position
        DataHasSystemAuditFields: Boolean;
        EnableFieldDict, UseSQL : Boolean;
        EnableOptDict: Boolean;
        FieldIsDict: Boolean;
        FieldIsOptDict: Boolean;
        LegacyDictFlags: Boolean; // archive older than the stamped encoding flags : replay the export grouping rules
        FieldsMatchedColumnEmpty: array[500] of Boolean;
        FieldsMatchedPartOfPK: array[500] of Boolean;
        FieldsOriginalColumnEmpty: array[500] of Boolean;
        OptSlotByName: Dictionary of [Text, Integer]; // dictionary file name -> its slot, one slot per distinct enum
        FieldsMatchedTypes: array[500] of Enum "TOO Fields Types";
        OrigFlatType: array[500] of Enum "TOO Fields Types";
        MatchedFieldRefType: array[500] of FieldType; // FieldRef.Type per matched column, cached for the hot field loop
        OrigFlatFieldRefType: array[500] of FieldType; // same, indexed by original (archive) field position
        LocalUserSecId: Guid;
        CompressedInstr: InStream;
        DataInStream: InStream;
        DictBase: Integer;
        DictFirstIdx: Integer; // first matched index of the FK dictionary columns, grouped after the plain ones
        FieldInDataCount: Integer;
        FieldMatchedCount: Integer;
        FieldPass: Integer; // column group of the field being read : plain, FK dictionary, option dictionary
        FieldsMatchedDictBase: array[500] of Integer; // base offset of this column's dictionary inside DictFlat
        FieldsMatchedID: array[500] of Integer;
        FieldsMatchedLen: array[500] of Integer;
        FieldsMatchedOriginalIndex: array[500] of Integer;
        FieldsOriginalIDList: array[500] of Integer;
        FieldsOriginalMatchedIndex: array[500] of Integer;
        FieldsOriginalTypeList: array[500] of Integer;
        FileRecordPosition: Integer;
        I: Integer;
        J: Integer;
        LastDictOrd: array[500] of Integer; // last ordinal decoded for this dictionary column, 0 = nothing cached
        LocalNbRecs: Integer;
        OptFirstIdx: Integer; // first matched index of the option dictionary columns, they are grouped at the end
        OptLoad: array[255] of Integer;         // load buffer, copied into the slot row
        // Option dictionary decoding : real member ordinals in a flat array per distinct enum of the table, reached
        // by a direct index from the record loop.
        OptOrdinals: array[64, 255] of Integer; // slot -> dense index -> real ordinal
        OptSlot: array[500] of Integer; // matched column -> slot
        OptSlotCount: Integer;
        OptSlotMembers: array[64] of Integer;   // member count per slot
        OptSlotNo: Integer;
        OrigFlatID: array[500] of Integer;
        OrigFlatLen: array[500] of Integer;
        Pass: Integer;
        PkFieldsMapped: Integer;
        RecorsNbUnChecked: Integer;
        HashAlgorithmType: Option MD5,SHA1,SHA256,SHA384,SHA512;
        OutStream: OutStream;
        CalulatedHash: Text;
        LastDictValue: array[500] of Text; // its already truncated value, see the dictionary loops
#if ONPREM
        // Only referenced by the SQL bulk-insert path, which is ONPREM-only.
        ExtraField: Record Field;
        DisabledIdxCount: Integer;
        FieldsExtraCount: Integer;
        FieldsExtraID: array[500] of Integer; // destination fields absent from the archive, filled with BC empty value
        IdxDisableMinRecs: Integer; // effective "Idx Disable Min. Records", 0 on the archive means use the default
        MatchedIDs: List of [Integer];
        CleanedErr: Text;
#endif
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
        OptSlotCount := 0;
        LegacyDictFlags := Archive.Version < PipouMgt.ArchiveFormatVersion();
        Clear(OptSlotByName);
        ArchiveFields.SetRange("Archive ID", Archive."Archive ID");
        ArchiveFields.SetRange("Table ID", ArchiveFile."Table ID");
        // Three passes : plain columns take the low matched indexes, FK dictionary columns the next ones, option
        // dictionary columns the high ones, so the record loop runs flat loops with no per field test. The original
        // (archive) index space is untouched, it still follows the archive order the row oriented path depends on.
        for Pass := 1 to 3 do begin
            I := 1;
            ArchiveFields.FindSet();
            repeat
                if Pass = 1 then begin
                    FieldsOriginalIDList[I] := ArchiveFields."Field ID";
                    FieldsOriginalTypeList[I] := ArchiveFields."Field Type";
                    // Chunk number matched between its two delimiters : an undelimited Contains also hits inside a
                    // longer number ("2," inside "12,", ",1" inside ",12,"), which silently flags a filled column as
                    // empty and shifts every column stream read after it.
                    FieldsOriginalColumnEmpty[I] := StrPos(',' + ArchiveFields."Empty In Chunks List" + ',', ',' + Format(ArchiveFile."Chunk No.") + ',') > 0;
                    FieldsOriginalMatchedIndex[I] := 0;
                    FieldInDataCount += 1;
                end;
                // Dictionary : ordinals are only written in column oriented files. From version 2 on, "Use Dictionary"
                // is what the export actually wrote. Archives built before the version was stamped only carry what the
                // detection planned, so the export rules have to be replayed for them : a column the export dropped
                // from the dictionary group carries plain values, and decoding those as ordinals reads a byte of text
                // as a dictionary index.
                FieldIsDict := ArchiveFields."Use Dictionary" and ArchiveFile."Column Storage";
                if FieldIsDict and LegacyDictFlags then
                    FieldIsDict := Archive."Enable Dictionaries" and not PipouMgt.IsFieldAnonymized(ArchiveFields, Archive.ClassifiedDataHandling);
                // Option and FK dictionaries never overlap : the FK detection only ever flags Code and Text columns
                FieldIsOptDict := FieldIsDict and (ArchiveFields."Field Type" = ArchiveFields."Field Type"::Option);
                if FieldIsOptDict then
                    FieldIsDict := false;
                FieldPass := 1;
                if FieldIsDict then
                    FieldPass := 2;
                if FieldIsOptDict then
                    FieldPass := 3;
                // Load matched field to import
                if FieldPass = Pass then
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
                                    if FieldIsDict then begin
                                        // Flagged even when the column is empty in this chunk : the decoding loop
                                        // still has to run over it to keep the bulk column index aligned.
                                        EnableFieldDict := true;
                                        // An empty column carries no ordinal at all : its dictionary is never read,
                                        // and an unused one is not even in the archive.
                                        if not FieldsOriginalColumnEmpty[I] then begin
                                            if not DictBaseByName.Get(ArchiveFields."Dictionary File Name", DictBase) then begin
                                                // Once per thread per parent : the whole dictionary is read into the flat list
                                                DictBase := ArchiveDict.LoadImportDictionary(Archive."Archive ID", ArchiveFields."Dictionary File Name", DictFlat);
                                                DictBaseByName.Set(ArchiveFields."Dictionary File Name", DictBase);
                                            end;
                                            FieldsMatchedDictBase[FieldMatchedCount] := DictBase;
                                        end;
                                    end;
                                    if FieldIsOptDict then begin
                                        EnableOptDict := true;
                                        // Flagged even when the column is empty in this chunk : the decoding loop
                                        // still has to run over it to keep the bulk column index aligned.
                                        if not FieldsOriginalColumnEmpty[I] then begin
                                            // One slot per distinct dictionary : several columns typed on the same
                                            // enum share one ordinal array, read once per table.
                                            if not OptSlotByName.Get(ArchiveFields."Dictionary File Name", OptSlotNo) then begin
                                                OptSlotNo := 0;
                                                if OptSlotCount < ArrayLen(OptOrdinals, 1) then begin
                                                    OptSlotCount += 1;
                                                    OptSlotMembers[OptSlotCount] := ArchiveDict.LoadOptionOrdinals(Archive."Archive ID", ArchiveFields."Dictionary File Name", OptLoad);
                                                    for J := 1 to OptSlotMembers[OptSlotCount] do
                                                        OptOrdinals[OptSlotCount, J] := OptLoad[J];
                                                    OptSlotNo := OptSlotCount;
                                                    OptSlotByName.Set(ArchiveFields."Dictionary File Name", OptSlotNo);
                                                end;
                                            end;
                                            OptSlot[FieldMatchedCount] := OptSlotNo;
                                        end;
                                    end;
                                    if Fields."No." > 2000000000 then
                                        DataHasSystemAuditFields := true;
                                end;
                        end else
                            // Handle missing field
                            if ArchiveFile."Chunk No." = 1 then
                                PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, EmptyRecID, StrSubstNo('Unable to match field in Table "%1" :\ Name : %2\ Caption : %3 \ID : %4 \Type : %5', TableMeta.Name, ArchiveFields."Field Name", ArchiveFields."Field Caption", ArchiveFields."Field ID", ArchiveFields."Field Type Name"));
                I += 1;
            until ArchiveFields.Next() = 0;
            if Pass = 1 then
                DictFirstIdx := FieldMatchedCount + 1; // index of the first FK dictionary encoded column
            if Pass = 2 then
                OptFirstIdx := FieldMatchedCount + 1; // index of the first option dictionary encoded column
        end;

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
                    Error('File "%1" decompression integrity verification failed.\Original data signature hash : %2\Decompressed data signature hash : %3', ArchiveFile."File Name", ArchiveFile."Uncompressed MD5 Hash", CalulatedHash);
                DataInStream.ResetPosition();
            end;
        end;
        Clear(CompressedInstr); // free ram from original compressed stream
        #endregion

        // Prepare columns streams
        if ArchiveFile."Column Storage" then
            for I := 1 to FieldMatchedCount do
                if not FieldsMatchedColumnEmpty[I] then
                    if not ColStoreMgt.GetOriginalfieldIDColumnInStr(FieldsOriginalIDList[FieldsMatchedOriginalIndex[I]], MatchedDataColInStream[I]) then
                        FieldsMatchedColumnEmpty[I] := true; // column not found

        #region SQL schema
#if ONPREM
        // Prepare SQL Bulk
        if (Archive."Import Use SQL Bulk") then begin
            // Only use sql bulk with bin format
            UseSQL := true;
            // Empty BLOB payload : always a zero-length byte array, and GetType() is a reflection lookup by string.
            // Build it once here instead of per BLOB field per record.
            GlobEmptyBlobBytes := GlobEmptyBlobBytes.CreateInstance(GlobDotNetType.GetType('System.Byte'), 0);
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
                        ExtraFieldRefType[FieldsExtraCount] := RecordRef.Field(ExtraField."No.").Type; // cached for the hot row loop
                        SQLAddBulkColumn(RecordRef.Field(ExtraField."No."), false);
                    end;
                until ExtraField.Next() = 0;

            // Also Add audit fields
            if not DataHasSystemAuditFields then
                SQLAddBulkColumnAudits();

            // Columns that hold the BC empty value for the whole chunk : matched columns absent from the archive
            // data, and destination fields absent from the archive altogether. Letting the DataTable pre-fill them
            // in NewRow() means the record loop only has to advance the column index.
            // Column indexes are zero based and follow the AddColumn order : matched fields first, then extra fields.
            for I := 1 to FieldMatchedCount do
                if FieldsMatchedColumnEmpty[I] then
                    SQLBulkmporterHelper.SetColumnEmptyDefault(I - 1, SQLColumnTypeName(RecordRef.Field(FieldsMatchedID[I]).Type));
            for I := 1 to FieldsExtraCount do
                SQLBulkmporterHelper.SetColumnEmptyDefault(FieldMatchedCount + I - 1, SQLColumnTypeName(ExtraFieldRefType[I]));
            // SQLOpen opened a row before any column existed : replace it so the first record gets the defaults too.
            // DefaultValue is applied when the DataRow is created, never retroactively.
            SQLBulkmporterHelper.BeginRow();
            RowOpened := true;

            // Drop the secondary indexes for the whole table import : maintaining and logging them row by row is
            // the bulk of the insert cost. Rebuilt once the last chunk of this table is imported (see Commit region).
            // Only above the configured record count : a rebuild is a full sorted build per index, so on a small
            // table it costs more than the row-by-row maintenance it saves.
            // Same lock + re-Get pattern as the truncate above, so concurrent threads on one table disable only once.
            // 0 = not set (archives created before this option existed) : fall back to the default threshold.
            IdxDisableMinRecs := Archive."Idx Disable Min. Records";
            if IdxDisableMinRecs = 0 then
                IdxDisableMinRecs := 10000; // default threshold, same as the field InitValue
            if (IdxDisableMinRecs > 0) and (Table."No. of Records" >= IdxDisableMinRecs) then begin
                ArchiveTable.LockTable();
                ArchiveTable.Get(Archive."Archive ID", ArchiveFile."Table ID");
                if not ArchiveTable."Indexes Disabled" then begin
                    // Keep the counts : 0 means the table had no index eligible for disabling, which is the
                    // difference between "the optimization did not run" and "it ran and found nothing to do".
                    DisabledIdxCount := SQLBulkmporterHelper.DisableSecondaryIndexes(GetSqlConnectionString(), BaseTableSQLName);
                    DisabledIdxCount += SQLBulkmporterHelper.DisableSecondaryIndexes(GetSqlConnectionString(), ExtTableSQLName);
                    ArchiveTable.Get(Archive."Archive ID", ArchiveFile."Table ID");
                    if not ArchiveTable."Indexes Disabled" then begin
                        ArchiveTable."Indexes Disabled" := true;
                        ArchiveTable."Disabled Indexes Count" := DisabledIdxCount;
                        ArchiveTable.Modify();
                    end;
                    Commit();
                end;
            end;
        end else
            // Just open recref for AL
            RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
#else
        // Just open recref for AL
        RecordRef.Open(ArchiveFile."Matched Table ID", false, Archive."Import Destination Company");
#endif
        #endregion

        // FieldRefs and their Type are constant per column : cache both once here instead of one FieldRef interop
        // lookup per field per record. The record buffer is opened once per chunk and reused for every record : no
        // Clear + Open between records. Safe because every non-empty matched column rewrites its value on each
        // record (empty and unmatched columns stay at their initial blank for the whole chunk), and Insert(false)
        // makes the platform assign a fresh SystemId on every insert.
        for I := 1 to FieldMatchedCount do begin
            MatchedFieldRef[I] := RecordRef.Field(FieldsMatchedID[I]);
            MatchedFieldRefType[I] := MatchedFieldRef[I].Type;
        end;
        for I := 1 to FieldInDataCount do
            if FieldsOriginalMatchedIndex[I] > 0 then begin
                OrigFlatFieldRef[I] := MatchedFieldRef[FieldsOriginalMatchedIndex[I]];
                OrigFlatFieldRefType[I] := MatchedFieldRefType[FieldsOriginalMatchedIndex[I]];
            end;

        #region Parse Records
        Thread.Status := Thread.Status::"Importing Data";
        Thread.Modify();
        Commit();
        case UseSQL of
#if ONPREM
            true:

                if ArchiveFile."Column Storage" then
            #region SQL-ColStore
                    // Column oriented
                    while (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs) do begin
                        for I := 1 to DictFirstIdx - 1 do begin
                            // Ignore empty column : not exported
                            if not FieldsMatchedColumnEmpty[I] then
                                case FieldsMatchedTypes[I] of
                                    "TOO Fields Types"::BLOB:
                                        AddBulkBlobValueFromBin(MatchedDataColInStream[I], RowColumns);
                                    "TOO Fields Types"::Media:
                                        AddBulkMediaValueFromBin(MatchedDataColInStream[I], RowColumns);
                                    "TOO Fields Types"::MediaSet:
                                        SQLAddBulkMediaSetValueFromBin(MatchedDataColInStream[I], RowColumns);

                                    "TOO Fields Types"::Text,
                                    "TOO Fields Types"::Code:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDataText);
                                            SQLBulkmporterHelper.AddRowValue(CopyStr(EvalDataText, 1, FieldsMatchedLen[I]), RowColumns);
                                        end;

                                    "TOO Fields Types"::DateFormula:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDataText);
                                            if not EvalDataText.StartsWith('<') then
                                                Evaluate(EvalDateFormula, '<' + EvalDataText + '>')
                                            else
                                                Evaluate(EvalDateFormula, EvalDataText);
                                            VariantVal := EvalDateFormula;
                                            SQLBulkmporterHelper.AddRowValue(VariantVal, RowColumns);
                                        end;

                                    "TOO Fields Types"::RecordID:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDataText);
                                            if EvalDataText = '' then
                                                EvalRecID := EmptyRecID
                                            else
                                                if not Evaluate(EvalRecID, EvalDataText.Replace('{', '').Replace('}', '')) then
                                                    EvalRecID := EmptyRecID; // Invalid Table or PK, cant parse RecordID
                                                                             // Convert then write RecordID to SQL binary format
                                            SQLAddBulkRecIDValueToSQLBin(EvalRecID);
                                        end;

                                    "TOO Fields Types"::Duration:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalBigInt);
                                            SQLBulkmporterHelper.AddRowValue(EvalBigInt, RowColumns);
                                        end;

                                    "TOO Fields Types"::Boolean:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalByte);
                                            if (EvalByte = 1) then
                                                SQLBulkmporterHelper.AddRowValue(true, RowColumns)
                                            else
                                                SQLBulkmporterHelper.AddRowValue(false, RowColumns);
                                        end;

                                    "TOO Fields Types"::Date:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDate);
                                            if EvalDate = 0D then
                                                SQLBulkmporterHelper.AddRowValueALDate(0, 0, 0, RowColumns)
                                            else
                                                // EvalDate = ClosingDate(EvalDate) only for closing dates → flag stored as 23:59:59 in SQL
                                                SQLBulkmporterHelper.AddRowValueALDate(Date2DMY(EvalDate, 3), Date2DMY(EvalDate, 2), Date2DMY(EvalDate, 1), RowColumns, EvalDate = ClosingDate(EvalDate));
                                        end;

                                    "TOO Fields Types"::Time:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalTime);
                                            if EvalTime = 0T then
                                                SQLBulkmporterHelper.AddRowValueALTime(0DT, RowColumns)
                                            else
                                                SQLBulkmporterHelper.AddRowValueALTime(CreateDateTime(DMY2Date(1, 1, 1753), EvalTime), RowColumns);
                                        end;

                                    "TOO Fields Types"::DateTime:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDateTime);
                                            SQLBulkmporterHelper.AddRowValue(EvalDateTime, RowColumns);
                                        end;

                                    "TOO Fields Types"::GUID:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalGuid);
                                            SQLBulkmporterHelper.AddRowValue(EvalGuid, RowColumns);
                                        end;

                                    "TOO Fields Types"::Decimal:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDec);
                                            SQLBulkmporterHelper.AddRowValue(EvalDec, RowColumns);
                                        end;

                                    "TOO Fields Types"::Option,
                                    "TOO Fields Types"::Integer:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalInt);
                                            SQLBulkmporterHelper.AddRowValue(EvalInt, RowColumns);
                                        end;

                                    "TOO Fields Types"::BigInteger:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalBigInt);
                                            SQLBulkmporterHelper.AddRowValue(EvalBigInt, RowColumns);
                                        end;
                                    else
                                        Error('Unsupported field type %1', FieldsMatchedTypes[I])
                                end;
                            // Column empty for the whole chunk : pre-filled by the DataTable default
                            // only the column index has to advance.
                            RowColumns += 1;
                        end;

            #region FK dict (SQL-ColStore)
                        // Same decoding as the AL column store path. The bulk column order follows this same array
                        // order (SQLAddBulkColumn loop), so splitting the loop keeps RowColumns aligned.
                        if EnableFieldDict then
                            for I := DictFirstIdx to OptFirstIdx - 1 do begin
                                if not FieldsMatchedColumnEmpty[I] then begin
                                    MatchedDataColInStream[I].Read(EvalByte);
                                    case EvalByte of
                                        0:
                                            SQLBulkmporterHelper.AddRowValue('', RowColumns);
                                        255: // sentinel
                                            begin
                                                MatchedDataColInStream[I].Read(EvalDataText); // dangling FK : literal written inline
                                                SQLBulkmporterHelper.AddRowValue(copystr(EvalDataText, 1, FieldsMatchedLen[I]), RowColumns);
                                            end;
                                        else begin
                                            if EvalByte <> LastDictOrd[I] then begin
                                                // Last value cache : a FK column repeats the same parent over consecutive rows,
                                                LastDictOrd[I] := EvalByte;
                                                LastDictValue[I] := copystr(DictFlat.Get(FieldsMatchedDictBase[I] + EvalByte), 1, FieldsMatchedLen[I]);
                                            end;
                                            SQLBulkmporterHelper.AddRowValue(LastDictValue[I], RowColumns);
                                        end;
                                    end;
                                end;
                                RowColumns += 1;
                            end;
            #endregion

            #region Option dict (SQL-ColStore)
                        // Dense byte back to the real member ordinal : a direct index into the ordinal array, no
                        // search at all on this side. Same bulk column alignment rule as the FK loop above.
                        if EnableOptDict then
                            for I := OptFirstIdx to FieldMatchedCount do begin
                                if not FieldsMatchedColumnEmpty[I] then begin
                                    MatchedDataColInStream[I].Read(EvalByte);
                                    if EvalByte = 255 then
                                        MatchedDataColInStream[I].Read(EvalInt) // not a declared member : real ordinal written inline
                                    else
                                        EvalInt := OptOrdinals[OptSlot[I], EvalByte + 1];
                                    SQLBulkmporterHelper.AddRowValue(EvalInt, RowColumns);
                                end;
                                RowColumns += 1;
                            end;
            #endregion

                        // Add not exported field (none PK)
                        // Fields absent from the archive : always empty, pre-filled by the DataTable defaults
                        // (SQLSetEmptyColumnDefaults). Only the column index has to advance.
                        RowColumns += FieldsExtraCount;

                        // Audit field
                        if not DataHasSystemAuditFields then begin
                            SQLBulkmporterHelper.AddRowValue(CurrentDateTime, RowColumns); // CreatedAt
                            SQLBulkmporterHelper.AddRowValue(LocalUserSecId, RowColumns + 1); // CreatedBy
                            SQLBulkmporterHelper.AddRowValue(CurrentDateTime, RowColumns + 2); // ModifiedAt
                            SQLBulkmporterHelper.AddRowValue(LocalUserSecId, RowColumns + 3); // ModifiedBy
                        end;

                        // Close Row
                        if (RowColumns <> NoColumns) then
                            Error(ErrColMisMatch);
                        SQLBulkmporterHelper.EndRow();

                        // Prepare next row if any
                        SQLBulkmporterHelper.BeginRow();
                        RowColumns := 0;

                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end
            #endregion
                else
            #region SQL-Row
                    // Row oriented
                    while (not DataInStream.EOS and (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs)) do begin
                        for I := 1 to FieldInDataCount do
                            if (FieldsOriginalMatchedIndex[I] = 0) or (FieldsOriginalColumnEmpty[I]) then begin
                                // Skip/Read instream byte without handling the value (when no mapping available for import)
                                case FieldsOriginalTypeList[I] of
                                    "TOO Fields Types"::BLOB:
                                        begin
                                            DataInStream.Read(EvalInt);
                                            DataInStream.Position := Min(DataInStream.Position + EvalInt, DataInStream.Length); // skip blob content
                                        end;
                                    "TOO Fields Types"::Media:
                                        begin
                                            // Length, Guid, Mime Type, Width, Height, Desciption, Content
                                            DataInStream.Read(EvalInt);
                                            if EvalInt > 0 then begin
                                                DataInStream.Position := DataInStream.Position + 16; // media guid
                                                DataInStream.Read(EvalDataText); // Mime Type
                                                DataInStream.Position := DataInStream.Position + 8; // Width, Height 2 x Integer (2x4=8)
                                                DataInStream.Read(EvalDataText);
                                                DataInStream.Position := Min(DataInStream.Position + EvalInt, DataInStream.Length); // skip blob content
                                            end;
                                        end;
                                    "TOO Fields Types"::MediaSet:
                                        begin
                                            // Media count, MediaSet ID, (Media Index, Length, Guid, Mime Type, Width, Height, Desciption, Content)[n]
                                            DataInStream.Read(GenericMediaCount);
                                            if GenericMediaCount > 0 then begin
                                                DataInStream.Position := DataInStream.Position + 16; // mediaset guid
                                                for GenericMediaI := 1 to GenericMediaCount do begin
                                                    DataInStream.Position := DataInStream.Position + 24; // media index (4) + length (4) + guid (16) = 24
                                                    DataInStream.Read(EvalDataText); // Mime Type
                                                    DataInStream.Position := DataInStream.Position + 8; // Width, Height : 2 x Integer (2x4=8)
                                                    DataInStream.Read(EvalDataText); // description
                                                    DataInStream.Position := Min(DataInStream.Position + EvalInt, DataInStream.Length); // skip blob content
                                                end;
                                            end;
                                        end;
                                    "TOO Fields Types"::Text,
                                    "TOO Fields Types"::Code,
                                    "TOO Fields Types"::DateFormula,
                                    "TOO Fields Types"::RecordID:
                                        DataInStream.Read(EvalDataText);
                                    // Fixed lengths skip :
                                    "TOO Fields Types"::Duration:
                                        DataInStream.Position := Min(DataInStream.Position + 8, DataInStream.Length);
                                    "TOO Fields Types"::Date:
                                        DataInStream.Position := Min(DataInStream.Position + 4, DataInStream.Length);
                                    "TOO Fields Types"::Time:
                                        DataInStream.Position := Min(DataInStream.Position + 4, DataInStream.Length);
                                    "TOO Fields Types"::DateTime:
                                        DataInStream.Position := Min(DataInStream.Position + 8, DataInStream.Length);
                                    "TOO Fields Types"::Boolean:
                                        DataInStream.Position := Min(DataInStream.Position + 1, DataInStream.Length);
                                    "TOO Fields Types"::GUID:
                                        DataInStream.Position := Min(DataInStream.Position + 16, DataInStream.Length);
                                    "TOO Fields Types"::Decimal:
                                        DataInStream.Position := Min(DataInStream.Position + 12, DataInStream.Length);
                                    "TOO Fields Types"::Option,
                                    "TOO Fields Types"::Integer:
                                        DataInStream.Position := Min(DataInStream.Position + 4, DataInStream.Length);
                                    "TOO Fields Types"::BigInteger:
                                        DataInStream.Position := Min(DataInStream.Position + 8, DataInStream.Length);
                                    // Unknown ???
                                    else
                                        DataInStream.Read(EvalDataText);
                                end;

                                if FieldsOriginalColumnEmpty[I] then
                                    // Column empty for the whole chunk : pre-filled by the DataTable default
                                    // (SQLSetEmptyColumnDefaults), only the column index has to advance.
                                    RowColumns += 1;
                            end else begin
                                case OrigFlatType[I] of
                                    "TOO Fields Types"::BLOB:
                                        AddBulkBlobValueFromBin(DataInStream, RowColumns);
                                    "TOO Fields Types"::Media:
                                        AddBulkMediaValueFromBin(DataInStream, RowColumns);
                                    "TOO Fields Types"::MediaSet:
                                        SQLAddBulkMediaSetValueFromBin(DataInStream, RowColumns);

                                    "TOO Fields Types"::Text,
                                    "TOO Fields Types"::Code:
                                        begin
                                            DataInStream.Read(EvalDataText);
                                            SQLBulkmporterHelper.AddRowValue(CopyStr(EvalDataText, 1, OrigFlatLen[I]), RowColumns);
                                        end;

                                    "TOO Fields Types"::DateFormula:
                                        begin
                                            DataInStream.Read(EvalDataText);
                                            if not EvalDataText.StartsWith('<') then
                                                Evaluate(EvalDateFormula, '<' + EvalDataText + '>')
                                            else
                                                Evaluate(EvalDateFormula, EvalDataText);
                                            VariantVal := EvalDateFormula;
                                            SQLBulkmporterHelper.AddRowValue(VariantVal, RowColumns);
                                        end;

                                    "TOO Fields Types"::RecordID:
                                        begin
                                            DataInStream.Read(EvalDataText);
                                            if EvalDataText = '' then
                                                EvalRecID := EmptyRecID
                                            else
                                                if not Evaluate(EvalRecID, EvalDataText.Replace('{', '').Replace('}', '')) then
                                                    EvalRecID := EmptyRecID; // Invalid Table or PK, cant parse RecordID
                                                                             // Convert then write RecordID to SQL binary format
                                            SQLAddBulkRecIDValueToSQLBin(EvalRecID);
                                        end;

                                    "TOO Fields Types"::Duration:
                                        begin
                                            DataInStream.Read(EvalBigInt);
                                            SQLBulkmporterHelper.AddRowValue(EvalBigInt, RowColumns);
                                        end;

                                    "TOO Fields Types"::Boolean:
                                        begin
                                            DataInStream.Read(EvalByte);
                                            if (EvalByte = 1) then
                                                SQLBulkmporterHelper.AddRowValue(true, RowColumns)
                                            else
                                                SQLBulkmporterHelper.AddRowValue(false, RowColumns);
                                        end;

                                    "TOO Fields Types"::Date:
                                        begin
                                            DataInStream.Read(EvalDate);
                                            if EvalDate = 0D then
                                                SQLBulkmporterHelper.AddRowValueALDate(0, 0, 0, RowColumns)
                                            else
                                                // EvalDate = ClosingDate(EvalDate) only for closing dates → flag stored as 23:59:59 in SQL
                                                SQLBulkmporterHelper.AddRowValueALDate(Date2DMY(EvalDate, 3), Date2DMY(EvalDate, 2), Date2DMY(EvalDate, 1), RowColumns, EvalDate = ClosingDate(EvalDate));
                                        end;

                                    "TOO Fields Types"::Time:
                                        begin
                                            DataInStream.Read(EvalTime);
                                            if EvalTime = 0T then
                                                SQLBulkmporterHelper.AddRowValueALTime(0DT, RowColumns)
                                            else
                                                SQLBulkmporterHelper.AddRowValueALTime(CreateDateTime(DMY2Date(1, 1, 1753), EvalTime), RowColumns);
                                        end;

                                    "TOO Fields Types"::DateTime:
                                        begin
                                            DataInStream.Read(EvalDateTime);
                                            SQLBulkmporterHelper.AddRowValue(EvalDateTime, RowColumns);
                                        end;

                                    "TOO Fields Types"::GUID:
                                        begin
                                            DataInStream.Read(EvalGuid);
                                            SQLBulkmporterHelper.AddRowValue(EvalGuid, RowColumns);
                                        end;

                                    "TOO Fields Types"::Decimal:
                                        begin
                                            DataInStream.Read(EvalDec);
                                            SQLBulkmporterHelper.AddRowValue(EvalDec, RowColumns);
                                        end;

                                    "TOO Fields Types"::Option,
                                    "TOO Fields Types"::Integer:
                                        begin
                                            DataInStream.Read(EvalInt);
                                            SQLBulkmporterHelper.AddRowValue(EvalInt, RowColumns);
                                        end;

                                    "TOO Fields Types"::BigInteger:
                                        begin
                                            DataInStream.Read(EvalBigInt);
                                            SQLBulkmporterHelper.AddRowValue(EvalBigInt, RowColumns);
                                        end;
                                    else
                                        Error('Unsupported field type %1', OrigFlatType[I])
                                end;
                                RowColumns += 1; // was the trailing statement of SQLAddBulkValueFromBin : advances the SQL bulk column index
                            end;

                        // Add not exported field (none PK)
                        // Fields absent from the archive : always empty, pre-filled by the DataTable defaults
                        // (SQLSetEmptyColumnDefaults). Only the column index has to advance.
                        RowColumns += FieldsExtraCount;

                        // Audit field
                        if not DataHasSystemAuditFields then begin
                            SQLBulkmporterHelper.AddRowValue(CurrentDateTime, RowColumns); // CreatedAt
                            SQLBulkmporterHelper.AddRowValue(LocalUserSecId, RowColumns + 1); // CreatedBy
                            SQLBulkmporterHelper.AddRowValue(CurrentDateTime, RowColumns + 2); // ModifiedAt
                            SQLBulkmporterHelper.AddRowValue(LocalUserSecId, RowColumns + 3); // ModifiedBy
                        end;

                        // Close Row
                        if (RowColumns <> NoColumns) then
                            Error(ErrColMisMatch);
                        SQLBulkmporterHelper.EndRow();

                        // Prepare next row if any
                        SQLBulkmporterHelper.BeginRow();
                        RowColumns := 0;

                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end;
            #endregion
#endif
            false:
                if ArchiveFile."Column Storage" then
                    #region AL-ColStore
                    // Column oriented
                    while (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs) do begin
                        for I := 1 to DictFirstIdx - 1 do
                            if not FieldsMatchedColumnEmpty[I] then
                                case MatchedFieldRefType[I] of
                                    FieldType::Blob:
                                        BlobMgt.ImportBlobBinData(MatchedFieldRef[I], MatchedDataColInStream[I]);

                                    FieldType::Media:
                                        begin
                                            BlobMgt.ImportMediaBinary(EvalGuid, MatchedDataColInStream[I]);
                                            MatchedFieldRef[I].Value := EvalGuid;
                                        end;

                                    FieldType::MediaSet:
                                        begin
                                            BlobMgt.ImportMediaSetBinary(EvalGuid, MatchedDataColInStream[I]);
                                            MatchedFieldRef[I].Value := EvalGuid;
                                        end;

                                    FieldType::Text,
                                    FieldType::Code:
                                        begin
                                            MatchedDataColInStream[I].Read(TextData);
                                            MatchedFieldRef[I].Value := CopyStr(TextData, 1, FieldsMatchedLen[I]); // cached Field.Len, avoids the FieldRef.Length interop read
                                        end;

                                    FieldType::DateFormula:
                                        begin
                                            MatchedDataColInStream[I].Read(TextData);
                                            if not TextData.StartsWith('<') then
                                                Evaluate(EvalDateFormula, '<' + TextData + '>')
                                            else
                                                Evaluate(EvalDateFormula, TextData);
                                            MatchedFieldRef[I].Value := EvalDateFormula;
                                        end;

                                    FieldType::RecordId:
                                        begin
                                            MatchedDataColInStream[I].Read(TextData);
                                            Evaluate(EvalRecID, TextData.Replace('{', '').Replace('}', ''));
                                            MatchedFieldRef[I].Value := EvalRecID;
                                        end;

                                    FieldType::Duration:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDuration);
                                            MatchedFieldRef[I].Value := EvalDuration;
                                        end;

                                    FieldType::Boolean:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalByte);
                                            // Unconditional write : the record buffer is reused across records
                                            MatchedFieldRef[I].Value := EvalByte = 1;
                                        end;

                                    FieldType::Date:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDate);
                                            MatchedFieldRef[I].Value := EvalDate;
                                        end;

                                    FieldType::Time:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalTime);
                                            MatchedFieldRef[I].Value := EvalTime;
                                        end;

                                    FieldType::DateTime:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDateTime);
                                            MatchedFieldRef[I].Value := EvalDateTime;
                                        end;

                                    FieldType::Option:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalOption);
                                            MatchedFieldRef[I].Value := EvalOption;
                                        end;

                                    FieldType::Guid:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalGuid);
                                            MatchedFieldRef[I].Value := EvalGuid;
                                        end;

                                    FieldType::Decimal:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalDec);
                                            MatchedFieldRef[I].Value := EvalDec;
                                        end;

                                    FieldType::Integer:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalInt);
                                            MatchedFieldRef[I].Value := EvalInt;
                                        end;

                                    FieldType::BigInteger:
                                        begin
                                            MatchedDataColInStream[I].Read(EvalBigInt);
                                            MatchedFieldRef[I].Value := EvalBigInt;
                                        end;

                                    // Unknown ???
                                    else begin
                                        MatchedDataColInStream[I].Read(TextData);
                                        MatchedFieldRef[I].Value := TextData;
                                    end;
                                end;
                        //if not EvaluateBinaryToBCField(BCField, MatchedDataColInStream[I]) then
                        //    PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, RecordRef.RecordId, StrSubstNo('Unable to parse value into field %1, stream position %2 : %3', BCField.Caption, DataInStream.Position, GetLastErrorText));

                        #region FK dict (AL-ColStore)
                        // Dictionary encoded columns are grouped at the end of the matched index space, so neither
                        // loop pays a per field test. Ordinal into the parent primary key values : one List.Get
                        // instead of reading the literal back out of the column stream.
                        if EnableFieldDict then
                            for I := DictFirstIdx to OptFirstIdx - 1 do
                                if not FieldsMatchedColumnEmpty[I] then begin
                                    MatchedDataColInStream[I].Read(EvalByte);
                                    case EvalByte of
                                        0:
                                            MatchedFieldRef[I].Value := '';
                                        255: // sentinel
                                            begin
                                                MatchedDataColInStream[I].Read(EvalDataText); // dangling FK : literal written inline
                                                MatchedFieldRef[I].Value := copystr(EvalDataText, 1, FieldsMatchedLen[I]);
                                            end;
                                        else begin
                                            if EvalByte <> LastDictOrd[I] then begin
                                                // Last value cache : a FK column repeats the same parent over consecutive rows,
                                                LastDictOrd[I] := EvalByte;
                                                LastDictValue[I] := copystr(DictFlat.Get(FieldsMatchedDictBase[I] + EvalByte), 1, FieldsMatchedLen[I]);
                                            end;
                                            MatchedFieldRef[I].Value := LastDictValue[I];
                                        end;
                                    end;
                                end;
                        #endregion

                        #region Option dict (AL-ColStore)
                        // Dense byte back to the real member ordinal : a direct index into the ordinal array, no
                        // search at all on this side.
                        if EnableOptDict then
                            for I := OptFirstIdx to FieldMatchedCount do
                                if not FieldsMatchedColumnEmpty[I] then begin
                                    MatchedDataColInStream[I].Read(EvalByte);
                                    if EvalByte = 255 then
                                        MatchedDataColInStream[I].Read(EvalOption) // not a declared member : real ordinal written inline
                                    else
                                        EvalOption := OptOrdinals[OptSlot[I], EvalByte + 1];
                                    MatchedFieldRef[I].Value := EvalOption;
                                end;
                        #endregion

                        if not TryInsertRecRef(RecordRef) then
                            PipouMgt.LogInsertRecErrorMessage(ArchiveFile, RecordRef.RecordId, GetLastErrorText());
                        // No Clear + Open : buffer reused, every non-empty column rewritten next record (see FieldRef cache above)
                        RecorsNbUnChecked += 1;
                        if RecorsNbUnChecked >= 500 then
                            UpdateImportProgress(RecorsNbUnChecked, FileRecordPosition, Table, ArchiveFile, Thread);
                    end
                #endregion
                else
                    #region AL-Row
                    // Row oriented
                    while (not DataInStream.EOS and (RecorsNbUnChecked + FileRecordPosition < LocalNbRecs)) do begin
                        for I := 1 to FieldInDataCount do
                            if (FieldsOriginalMatchedIndex[I] = 0) or FieldsOriginalColumnEmpty[I] then
                                //SkipBinaryBytesBCField(FieldsOriginalTypeList[I], DataInStream)
                                // Skip/Read instream byte without handling the value (when no mapping available for import)
                                case FieldsOriginalTypeList[I] of
                                    "TOO Fields Types"::BLOB:
                                        begin
                                            DataInStream.Read(EvalInt);
                                            DataInStream.Position := Min(DataInStream.Position + EvalInt, DataInStream.Length); // skip blob content
                                        end;
                                    "TOO Fields Types"::Media:
                                        begin
                                            // Length, Guid, Mime Type, Width, Height, Desciption, Content
                                            DataInStream.Read(EvalInt);
                                            if EvalInt > 0 then begin
                                                DataInStream.Position := DataInStream.Position + 16; // media guid
                                                DataInStream.Read(EvalDataText); // Mime Type
                                                DataInStream.Position := DataInStream.Position + 8; // Width, Height 2 x Integer (2x4=8)
                                                DataInStream.Read(EvalDataText);
                                                DataInStream.Position := Min(DataInStream.Position + EvalInt, DataInStream.Length); // skip blob content
                                            end;
                                        end;
                                    "TOO Fields Types"::MediaSet:
                                        begin
                                            // Media count, MediaSet ID, (Media Index, Length, Guid, Mime Type, Width, Height, Desciption, Content)[n]
                                            DataInStream.Read(GenericMediaCount);
                                            if GenericMediaCount > 0 then begin
                                                DataInStream.Position := DataInStream.Position + 16; // mediaset guid
                                                for GenericMediaI := 1 to GenericMediaCount do begin
                                                    DataInStream.Position := DataInStream.Position + 24; // media index (4) + length (4) + guid (16) = 24
                                                    DataInStream.Read(EvalDataText); // Mime Type
                                                    DataInStream.Position := DataInStream.Position + 8; // Width, Height : 2 x Integer (2x4=8)
                                                    DataInStream.Read(EvalDataText); // description
                                                    DataInStream.Position := Min(DataInStream.Position + EvalInt, DataInStream.Length); // skip blob content
                                                end;
                                            end;
                                        end;
                                    "TOO Fields Types"::Text,
                                    "TOO Fields Types"::Code,
                                    "TOO Fields Types"::DateFormula,
                                    "TOO Fields Types"::RecordID:
                                        DataInStream.Read(EvalDataText);
                                    // Fixed lengths skip :
                                    "TOO Fields Types"::Duration:
                                        DataInStream.Position := Min(DataInStream.Position + 8, DataInStream.Length);
                                    "TOO Fields Types"::Date:
                                        DataInStream.Position := Min(DataInStream.Position + 4, DataInStream.Length);
                                    "TOO Fields Types"::Time:
                                        DataInStream.Position := Min(DataInStream.Position + 4, DataInStream.Length);
                                    "TOO Fields Types"::DateTime:
                                        DataInStream.Position := Min(DataInStream.Position + 8, DataInStream.Length);
                                    "TOO Fields Types"::Boolean:
                                        DataInStream.Position := Min(DataInStream.Position + 1, DataInStream.Length);
                                    "TOO Fields Types"::GUID:
                                        DataInStream.Position := Min(DataInStream.Position + 16, DataInStream.Length);
                                    "TOO Fields Types"::Decimal:
                                        DataInStream.Position := Min(DataInStream.Position + 12, DataInStream.Length);
                                    "TOO Fields Types"::Option,
                                    "TOO Fields Types"::Integer:
                                        DataInStream.Position := Min(DataInStream.Position + 4, DataInStream.Length);
                                    "TOO Fields Types"::BigInteger:
                                        DataInStream.Position := Min(DataInStream.Position + 8, DataInStream.Length);
                                    // Unknown ???
                                    else
                                        DataInStream.Read(EvalDataText);
                                end
                            else
                                case OrigFlatFieldRefType[I] of
                                    FieldType::Blob:
                                        BlobMgt.ImportBlobBinData(OrigFlatFieldRef[I], DataInStream);

                                    FieldType::Media:
                                        begin
                                            BlobMgt.ImportMediaBinary(EvalGuid, DataInStream);
                                            OrigFlatFieldRef[I].Value := EvalGuid;
                                        end;

                                    FieldType::MediaSet:
                                        begin
                                            BlobMgt.ImportMediaSetBinary(EvalGuid, DataInStream);
                                            OrigFlatFieldRef[I].Value := EvalGuid;
                                        end;

                                    FieldType::Text,
                                    FieldType::Code:
                                        begin
                                            DataInStream.Read(TextData);
                                            OrigFlatFieldRef[I].Value := CopyStr(TextData, 1, OrigFlatLen[I]); // cached Field.Len, avoids the FieldRef.Length interop read
                                        end;

                                    FieldType::DateFormula:
                                        begin
                                            DataInStream.Read(TextData);
                                            if not TextData.StartsWith('<') then
                                                Evaluate(EvalDateFormula, '<' + TextData + '>')
                                            else
                                                Evaluate(EvalDateFormula, TextData);
                                            OrigFlatFieldRef[I].Value := EvalDateFormula;
                                        end;

                                    FieldType::RecordId:
                                        begin
                                            DataInStream.Read(TextData);
                                            Evaluate(EvalRecID, TextData.Replace('{', '').Replace('}', ''));
                                            OrigFlatFieldRef[I].Value := EvalRecID;
                                        end;

                                    FieldType::Duration:
                                        begin
                                            DataInStream.Read(EvalDuration);
                                            OrigFlatFieldRef[I].Value := EvalDuration;
                                        end;

                                    FieldType::Boolean:
                                        begin
                                            DataInStream.Read(EvalByte);
                                            // Unconditional write : the record buffer is reused across records
                                            OrigFlatFieldRef[I].Value := EvalByte = 1;
                                        end;

                                    FieldType::Date:
                                        begin
                                            DataInStream.Read(EvalDate);
                                            OrigFlatFieldRef[I].Value := EvalDate;
                                        end;

                                    FieldType::Time:
                                        begin
                                            DataInStream.Read(EvalTime);
                                            OrigFlatFieldRef[I].Value := EvalTime;
                                        end;

                                    FieldType::DateTime:
                                        begin
                                            DataInStream.Read(EvalDateTime);
                                            OrigFlatFieldRef[I].Value := EvalDateTime;
                                        end;

                                    FieldType::Option:
                                        begin
                                            DataInStream.Read(EvalOption);
                                            OrigFlatFieldRef[I].Value := EvalOption;
                                        end;

                                    FieldType::Guid:
                                        begin
                                            DataInStream.Read(EvalGuid);
                                            OrigFlatFieldRef[I].Value := EvalGuid;
                                        end;

                                    FieldType::Decimal:
                                        begin
                                            DataInStream.Read(EvalDec);
                                            OrigFlatFieldRef[I].Value := EvalDec;
                                        end;

                                    FieldType::Integer:
                                        begin
                                            DataInStream.Read(EvalInt);
                                            OrigFlatFieldRef[I].Value := EvalInt;
                                        end;

                                    FieldType::BigInteger:
                                        begin
                                            DataInStream.Read(EvalBigInt);
                                            OrigFlatFieldRef[I].Value := EvalBigInt;
                                        end;

                                    // Unknown ???
                                    else begin
                                        DataInStream.Read(TextData);
                                        OrigFlatFieldRef[I].Value := TextData;
                                    end;
                                end;
                        //if not EvaluateBinaryToBCField(BCField, DataInStream) then
                        //    PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, RecordRef.RecordId, StrSubstNo('Unable to parse value into field %1, stream position %2', BCField.Caption, DataInStream.Position));
                        if not TryInsertRecRef(RecordRef) then
                            PipouMgt.LogInsertRecErrorMessage(ArchiveFile, RecordRef.RecordId, GetLastErrorText());
                        // No Clear + Open : buffer reused, every non-empty column rewritten next record (see FieldRef cache above)
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
            Clear(ColStoreMgt); // free memory from column datas

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
                SelectLatestVersion();
                // LockTable + Get by PK = row-level UPDLOCK, avoids table/range lock for BC < 23 (before tri-state lock versions)
                LockedArchiveFile.LockTable(true);
                LockedArchiveFile.SetRange("Archive Name", ArchiveFile."Archive Name");
                LockedArchiveFile.SetRange("Archive ID", ArchiveFile."Archive ID");
                LockedArchiveFile.SetRange("File Name", ArchiveFile."File Name");
                LockedArchiveFile.ModifyAll(Imported, true, false); // Avoid double sql round trip get + modify
                Commit();

                // Last chunk of this table (whatever thread fed the others) : put the secondary indexes back.
                // "Import Completed" is a FlowField over the files still flagged not imported, so it only turns
                // true once every chunk of the table is committed.
                SelectLatestVersion();
                ArchiveTable.LockTable();
                ArchiveTable.Get(Archive."Archive ID", ArchiveFile."Table ID");
                ArchiveTable.CalcFields("Import Completed");
                if ArchiveTable."Indexes Disabled" and ArchiveTable."Import Completed" then begin
                    Thread.Status := Thread.Status::"Rebuilding Indexes";
                    Thread.Modify();
                    Commit();
                    // Returns how many are STILL disabled : anything but 0 means a rebuild did not go through
                    DisabledIdxCount := SQLBulkmporterHelper.RebuildDisabledIndexes(GetSqlConnectionString(), BaseTableSQLName);
                    DisabledIdxCount += SQLBulkmporterHelper.RebuildDisabledIndexes(GetSqlConnectionString(), ExtTableSQLName);
                    ArchiveTable.Get(Archive."Archive ID", ArchiveFile."Table ID");
                    ArchiveTable."Indexes Disabled" := false;
                    ArchiveTable."Disabled Indexes Count" := DisabledIdxCount;
                    ArchiveTable.Modify();
                    Commit();
                    if DisabledIdxCount > 0 then
                        PipouMgt.LogParsingFieldWarningMessage(ArchiveFile, EmptyRecID, StrSubstNo('%1 secondary indexes or SIFT views are still disabled on table "%2" after the rebuild.', DisabledIdxCount, Table."Table Name"));
                end;
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
                LockedArchiveFile.SetRange("Archive Name", ArchiveFile."Archive Name");
                LockedArchiveFile.SetRange("Archive ID", ArchiveFile."Archive ID");
                LockedArchiveFile.SetRange("File Name", ArchiveFile."File Name");
                LockedArchiveFile.ModifyAll(Imported, true, false); // Avoid double sql round trip get + modify
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
            UpdateThreadProgress(Thread, Table."Table Name", ArchiveFile."File Name", Round(FileRecordPosition / ArchiveFile."Number Of Recs" * 100, 1, '<'), TotalProceedRec);
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
        AllObj.Get(AllObj."Object Type"::Table, OpenTableID);
        TableOriginalApp.Get(AllObj."App Runtime Package ID");
        SQLFilter := '';
        SQLSelect := '';
        TableCompanyName := FromCompanyName;
        NoColumns := 0;
        Clear(ListOfFieldInTableExt);
        Clear(ListOfFieldInTableExtAppID);
        Clear(ListOfSQLField);

        // Get SQL Table Name
        SourceTableName := SQLEscapeChar(TableMeta.Name);
        if TableMeta.DataPerCompany then
            BaseTableSQLName := StrSubstNo('%1$%2$%3', TableCompanyName, SourceTableName, DelChr(TableOriginalApp.ID, '=', '{}').ToLower())
        else
            BaseTableSQLName := StrSubstNo('%1$%2', SourceTableName, DelChr(TableOriginalApp.ID, '=', '{}').ToLower());
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
                PublishedApp.SetFilter(ID, '<>%1', TableOriginalApp.ID);
                PublishedApp.SetRange("Runtime Package ID", Fields."App Runtime Package ID");
                PublishedApp.SetRange(Installed, true);
                if PublishedApp.FindFirst() then begin
                    ListOfFieldInTableExt.Add(Fields."No.");
                    ListOfFieldInTableExtAppID.Add(PublishedApp.ID);
                end;
            until Fields.Next() = 0;

        // prepare first row
        SQLBulkmporterHelper.BeginRow();
        RowOpened := true;
        RowColumns := 0;
    end;
    #endregion

    #region Column
    // Maps an AL field type to the DataTable type name understood by BulkImporterExt.
    // Shared by SQLAddBulkColumn and SQLSetEmptyColumnDefaults so the column type and its empty default never diverge.
    local procedure SQLColumnTypeName(FldType: FieldType): Text
    begin
        case FldType of
            FldType::Text,
            FldType::Code,
            FldType::DateFormula:
                exit('String');
            FldType::Boolean,
            FldType::Integer,
            FldType::Option:
                exit('Int32');
            FldType::BigInteger,
            FldType::Duration:
                exit('Int64');
            FldType::Decimal:
                exit('Decimal');
            FldType::Time,
            FldType::Date,
            FldType::DateTime:
                exit('DateTime');
            FldType::Guid,
            FldType::Media,
            FldType::MediaSet:
                exit('GUID');
            FldType::Blob:
                exit('blob');
            FldType::RecordId:
                exit('varbinary'); // written as SQL binary by SQLAddBulkRecIDValueToSQLBin
        // TableFilter type is in BC runtime dll
        end;
    end;

    procedure SQLAddBulkColumn(FieldRef: FieldRef; IsPartOfPK: Boolean)
    var
        IndexOfFieldExt: Integer;
        Type: Text;
    begin
        Type := SQLColumnTypeName(FieldRef.Type);
        IndexOfFieldExt := ListOfFieldInTableExt.IndexOf(FieldRef.Number);
        if IndexOfFieldExt > 0 then begin
            SQLBulkmporterHelper.AddColumn(SQLEscapeChar(FieldRef.Name) + '$' + DelChr(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}').ToLower(), Type, IsPartOfPK);
            ListOfSQLField.Add(SQLEscapeChar(FieldRef.Name) + '$' + DelChr(ListOfFieldInTableExtAppID.Get(IndexOfFieldExt), '=', '{}').ToLower() + ' : ' + Type);
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
        MemoryStream: DotNet MemoryStream;
        BlobInStr: InStream;
        Length: Integer;
        OutStr: OutStream;
    begin
        // dot net bulk insert does not support stream, we need to convert it to Byte array
        InStr.Read(Length);
        if Length <= 0 then begin
            // Empty blob : reuse the shared zero-length byte array
            SQLBulkmporterHelper.AddRowValue(GlobEmptyBlobBytes, ColumnZeroBaseIndex);
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
        Clear(TempBlob);
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
    #endregion

    #region Add FIELD Value
    procedure SQLAddBulkRowValue(FieldValue: FieldRef)
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
                    EvalDateTime := FieldValue.Value;
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

    #region Add BIN Value
    local procedure AddBulkBlobValueFromBin(var InStr: InStream; ColumnZeroBaseIndex: Integer)
    var
        TempBlob: Codeunit "Temp Blob";
        MemoryStream: DotNet MemoryStream;
        BlobInStr: InStream;
        Length: Integer;
        OutStr: OutStream;
    begin
        // dot net bulk insert does not support stream, we need to convert it to Byte array
        InStr.Read(Length);
        if Length <= 0 then begin
            // Empty blob : reuse the shared zero-length byte array
            SQLBulkmporterHelper.AddRowValue(GlobEmptyBlobBytes, ColumnZeroBaseIndex);
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

    #region Send Bulk
    [TryFunction]
    procedure SQLCommitBulkInserts(UseTableLock: Boolean)
    begin
        // UseTableLock = false → per-row locks, lets several threads bulk-insert the same table at once
        SQLBulkmporterHelper.WriteToServer(GetSqlConnectionString(), BaseTableSQLName, UseTableLock);
    end;
    #endregion

    #region internal
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
        Sqlhelper: Codeunit "TOO SQL Helper";
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
        MatchedDataColInStream: array[512] of InStream;
        // FK dictionaries loaded by this thread : every parent shares one flat list, looked up by base offset + ordinal.
        // Eager load, roughly 150-250 MB per million entries per thread (threads do not share memory).
        ArchiveDict: Record "TOO Pipou Archive Dict.";
        DictFlat: List of [Text];
        DictBaseByName: Dictionary of [Text, Integer];
        EvalDataText: Text;
        GenericMediaCount: Integer;
        GenericMediaI: Integer;
#if ONPREM
        TableMeta: Record "Table Metadata";
        RowOpened: Boolean;
        NoColumns, RowColumns : Integer;
        BaseTableSQLName, ConnectionString, ExtTableSQLName, SQLFilter, SQLSelect, TableCompanyName : Text;
        SQLBulkmporterHelper: DotNet TOOSQLBulkImporterExt;
        EmptyGuid: Guid;
        BlogMgt: Codeunit "TOO Pipou Blob Mgt.";
        ListOfFieldInTableExtAppID: List of [Guid];
        ListOfFieldInTableExt: List of [Integer];
        ListOfSQLField: List of [Text];
        EmptyRecID: RecordId;
        VariantVal: Variant;
        GlobEmptyBlobBytes: DotNet Array; // System.Array
        GlobDotNetType: DotNet Type; // System.Type
        ErrColMisMatch: Label 'The number of values passed is different than the column definition.';
        ExtraFieldRefType: array[500] of FieldType; // FieldRef.Type per extra (not in archive) column
    //SQLHelper: Codeunit "TOO SQL Helper Bulk Insert";
#endif
}