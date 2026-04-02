codeunit 51005 "TOO Pipou Export Data"
{
    TableNo = "TOO Pipou Thread";


    #region MultiThrd Exp
    procedure MultiThreadExport(var Archive: Record "TOO Pipou Archive")
    var
        Win: Dialog;
        Progress: Label 'Exporting Data from company #1####\-\Elapsed time : #2########\ Estimated duration : #3#######\-\Global progression :\#4#########\Records : #6######\Compressed Size (KB) : #7#######-\#8######\-\#9######\-\#10######\-\#11######\-\#12######\-\#13######';
        NothingToImportLbl: Label 'There is nothing left to import for selected table. Reset the archive import state to redo the import.';
        RecProceed: Integer;
        TotFileSize: Decimal;
        TotCompSize: Decimal;
        ElapsedTime: Duration;
        ThreadTxt: Text;
        Thread: Record "TOO Pipou Thread";
        SessionID: Integer;
        AllThreadCompleted: Boolean;
        RemDuration: Duration;
        RemProgress: Decimal;
        GlobalProgress: Decimal;
        OtherArchive: Record "TOO Pipou Archive";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        ArchiveFiles: Record "TOO Pipou Archive Files";
        ErrorThrown: Boolean;
        ErrorMessage: Text;
        ArchTotalRecSize: Integer;
    begin
        ThreadHelper.CheckThreadsRunning();

        // Verify Archive
        Archive.TestField("Archive ID");
        Archive.TestField("Number of Threads");
        Archive.CalcFields("No. Tables");
        Archive.TestField("No. Tables");
        Archive.TestField("Total Records");
        Archive.TestField("Process Status", Archive."Process Status"::"⌛ Exporting");
        if (Archive."Number of Threads" < 1) or (Archive."Number of Threads" > 6) then
            Error('The number of threads to run the process must be within 1-6 range.');

        // Remove any other pending/failed export
        OtherArchive.SetFilter("Archive ID", '<>%1', Archive."Archive ID");
        OtherArchive.SetRange("Process Status", OtherArchive."Process Status"::"⌛ Exporting");
        OtherArchive.DeleteAll(true);

        // Reset other archive process state
        OtherArchive.SetFilter("Archive ID", '<>%1', Archive."Archive ID");
        OtherArchive.ModifyAll("Process Status", OtherArchive."Process Status"::" ");

        // Split tables ranges across threads
        ThreadHelper.CreateExportThreads(Archive);

        // Calc total rec to export based on selected tables
        ArchiveTables.SetRange("Archive ID", Archive."Archive ID");
        ArchiveTables.CalcSums("No. of Records");
        ArchTotalRecSize := ArchiveTables."No. of Records";
        if ArchTotalRecSize = 0 then
            error(NothingToImportLbl);

        // Set state to exporting
        Archive."Process Status" := Archive."Process Status"::"⌛ Exporting";
        Archive."Process Started At" := CurrentDateTime;
        Archive.Modify();
        Commit();

        if Archive."Number of Threads" = 1 then begin
            // Debug purpose - foreground run
            Win.Open('Exporting...');
            Thread.Get(1);
            Run(Thread);
            RecProceed := Thread."Total Rec. Proceed";
            TotFileSize := Thread."Files Size (KB)";
            TotCompSize := Thread."Files Compressed Size (KB)";
            Win.Close();
        end else begin
            Win.Open('Starting Threads...');
            // Start sessions
            Thread.Get(1);
            StartSession(SessionID, Codeunit::"TOO Pipou Export Data", CompanyName, Thread);
            if Archive."Number of Threads" > 1 then begin
                Thread.Get(2);
                StartSession(SessionID, Codeunit::"TOO Pipou Export Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 2 then begin
                Thread.Get(3);
                StartSession(SessionID, Codeunit::"TOO Pipou Export Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 3 then begin
                Thread.Get(4);
                StartSession(SessionID, Codeunit::"TOO Pipou Export Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 4 then begin
                Thread.Get(5);
                StartSession(SessionID, Codeunit::"TOO Pipou Export Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 5 then begin
                Thread.Get(6);
                StartSession(SessionID, Codeunit::"TOO Pipou Export Data", CompanyName, Thread);
            end;
            Win.Close();

            StartDT := CurrentDateTime;

            // Monitor thread until all data proceed
            Win.Open(Progress);
            Win.Update(1, Archive."Exported From Company");

            while (not AllThreadCompleted) do begin
                sleep(900);

                AllThreadCompleted := true; // false if any thread not completed
                RecProceed := 0;
                TotFileSize := 0;
                TotCompSize := 0;

                // Thread 1 :
                ThreadTxt := ThreadHelper.UpdateThreadProgress(1, AllThreadCompleted, ErrorThrown, ErrorMessage, RecProceed, TotFileSize, TotCompSize, Archive);
                Win.Update(8, ThreadTxt);
                if ErrorThrown then ThrowError(Archive, ErrorMessage);

                // Thread 2 :
                if Archive."Number of Threads" > 1 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(2, AllThreadCompleted, ErrorThrown, ErrorMessage, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(9, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 3 :
                if Archive."Number of Threads" > 2 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(3, AllThreadCompleted, ErrorThrown, ErrorMessage, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(10, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 4 :
                if Archive."Number of Threads" > 3 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(4, AllThreadCompleted, ErrorThrown, ErrorMessage, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(11, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 5 :
                if Archive."Number of Threads" > 4 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(5, AllThreadCompleted, ErrorThrown, ErrorMessage, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(12, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 6 :
                if Archive."Number of Threads" > 5 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(6, AllThreadCompleted, ErrorThrown, ErrorMessage, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(13, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;

                // Global progression
                GlobalProgress := ((RecProceed / ArchTotalRecSize) + (RecProceed / Archive."Total Records")) / 2;
                Win.Update(4, PipouMgt.ProgressBar(GlobalProgress));
                Win.Update(6, Format(RecProceed) + ' / ' + Format(Archive."Total Records"));
                Win.Update(7, Format(Round(TotCompSize, 1)));

                // Elapsed time
                ElapsedTime := Round(CurrentDateTime - StartDT, 1000);
                Win.Update(2, ElapsedTime);
                // Estimate remaining (after 1% progress)
                if (GlobalProgress >= 0.01) and (ArchTotalRecSize > 0) then begin
                    // multiply elapsed time by remaining % progression (if 25% = x3, 50% = x1, if 75% = x0.33)
                    RemProgress := (1 - GlobalProgress) / GlobalProgress;
                    // round by 10s
                    RemDuration := Round(ElapsedTime * RemProgress + 5000, 10000, '>');
                    Win.Update(3, RemDuration);
                end;
            end;
        end;
        // Finished
    end;

    local procedure ThrowError(var Archive: Record "TOO Pipou Archive"; Msg: Text)
    var
        Thread: Record "TOO Pipou Thread";
        ActiveSession: Record "Active Session";
    begin
        // Kill all other threads
        Thread.SetRange("Archive ID", Archive."Archive ID");
        if Thread.FindSet() then
            repeat
                if (Thread."Session ID" <> 0) and (Thread.Status <> Thread.Status::"Completed ✅") then begin
                    ActiveSession.SetRange("Session ID", Thread."Session ID");
                    if not ActiveSession.IsEmpty then
                        StopSession(Thread."Session ID", 'Stopped by mutex error in another thread');
                end;
            until Thread.Next() = 0;
        // Stop the process and remove partially created archive (along with sub file and meta)
        if Archive.Get(Archive."Archive Name", Archive."Archive ID") then begin
            Archive.Delete(true);
            Commit();
        end;
        Error(Msg);
    end;
    #endregion

    #region OnRun (Thread)
    trigger OnRun()
    var
        Archive: Record "TOO Pipou Archive";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        OtherThreads: Record "TOO Pipou Thread";
        ArchFiles: Record "TOO Pipou Archive Files";
    begin
        // Set thread status as started
        Rec."Session ID" := SessionId();
        Rec.Status := Rec.Status::"Exporting Data";
        Rec.Modify();
        Commit();

        // Table range to proceed
        ArchiveTables.ReadIsolation := ArchiveTables.ReadIsolation::ReadUncommitted;
        ArchiveTables.SetRange("Archive ID", Rec."Archive ID");
        if Rec."Thread No." in [0, 1] then
            // Thread 1 or unaffected
            ArchiveTables.SetRange("Affected Thread", 0, Rec."Thread No.")
        else
            // Thread 2+
            ArchiveTables.SetRange("Affected Thread", Rec."Thread No.");
        Archive.Get(Rec."Archive Name", Rec."Archive ID");

        // Init
        CR[1] := 13; // Carriage return, '\r'
        LF[1] := 10; // Line feed, '\n'
        PipouMgt.Initialize(Archive."Blob Max Size", Archive.ClassifiedDataHandling);

        // Loop tables
        LastThreadUpdateDT := CurrentDateTime;
        if ArchiveTables.FindSet() then
            repeat
                if not ExportTableData(Rec, Archive, ArchiveTables) then begin
                    PipouMgt.LogALErrorMessage(ArchiveFile, GetLastErrorText(), GetLastErrorCallStack());
                    Rec.Status := Rec.Status::"❌ Error";
                    Rec."Error Message" := GetLastErrorText();
                    Rec.Modify();
                    Commit();
                    exit;
                end;
            until ArchiveTables.Next() = 0;

        // All thread completed, update archive + remove threads
        OtherThreads.SetRange("Archive ID", Archive."Archive ID");
        OtherThreads.SetFilter("Thread No.", '<>%1', Rec."Thread No.");
        OtherThreads.SetFilter(Status, '<>%1', OtherThreads.Status::"Completed ✅");
        if OtherThreads.IsEmpty() then begin
            Archive.Get(Archive."Archive Name", Archive."Archive ID");
            Archive."Process Status" := Archive."Process Status"::"✅ Exported";
            // Count files
            ArchFiles.SetRange("Archive ID", Archive."Archive ID");
            ArchFiles.SetRange("Archive Name", Archive."Archive Name");
            Archive."No. Files" := ArchFiles.Count();
            // Count records and file size
            OtherThreads.Reset();
            OtherThreads.SetRange("Archive ID", Archive."Archive ID");
            OtherThreads.SetRange(Status);
            OtherThreads.CalcSums("Total Rec. Proceed", "Files Size (KB)", "Files Compressed Size (KB)");
            Archive."Total Records" := OtherThreads."Total Rec. Proceed";
            Archive."Files Size (KB)" := OtherThreads."Files Size (KB)";
            Archive."Files Compressed Size (KB)" := OtherThreads."Files Compressed Size (KB)";
            if Archive."Files Size (KB)" > 0 then
                Archive."Compression Ratio (%)" := 100 * (1 - (Archive."Files Compressed Size (KB)" / Archive."Files Size (KB)"));
            Archive.Modify();
            Commit();
            // Remove all threads  1sec later (in case GUI waiting for Completed state)
            sleep(1000);
            OtherThreads.Reset();
            OtherThreads.SetRange("Archive ID", Archive."Archive ID");
            OtherThreads.DeleteAll();
        end else begin
            // Mark thread as completed
            Rec.Status := Rec.Status::"Completed ✅";
            Rec.Modify();
        end;
        Commit();
    end;
    #endregion

    #region ExportTbleData
    [TryFunction]
    procedure ExportTableData(var Thread: Record "TOO Pipou Thread"; var Archive: Record "TOO Pipou Archive"; var Table: Record "TOO Pipou Archive Tables")
    var
        RecRef: RecordRef;
        Tablefields: Record "TOO Pipou Archive Fields";
        Field: Record Field;
        FieldIDList: array[500] of Integer;
        FieldNeedEscapeList: array[500] of Boolean;
        FieldTypeList: array[500] of Enum "TOO Fields Types";
        FieldAllEmpty: array[500] of Boolean;
        FieldDataClassifed: array[500] of Boolean;
        I: Integer;
        FieldsCount: Integer;
        EnableColStore: Boolean;
        UnCheckedPos: Integer;
        TableRecPos: Integer;
        FieldRefArr: array[500] of FieldRef;
    begin
        // Ignore export of it self
        if Table."Table ID" IN [Database::"TOO Pipou Archive Files", Database::"TOO Pipou Archive", database::"TOO Pipou Import Log"] then
            exit;

        // Open Record
        RecRef.Open(Table."Table ID", false, Archive."Exported From Company");
        if Archive."Diff. Export Start DT" <> 0DT then begin
            // AL Differential export
            RecRef.Field(RecRef.SystemCreatedAtNo).SetFilter('>%1', Archive."Diff. Export Start DT");
            Table."No. of Records" := RecRef.Count(); // overide number of rec counted
        end;
        if Table."No. of Records" = 0 then exit;

        // Enable transposition on 100+ records
        if Archive."Enable Columns Transcoding" then
            EnableColStore := (Table."No. of Records" > 100);

        #region Field definition
        // Store fields ID in array for faster reference
        Tablefields.ReadIsolation := Tablefields.ReadIsolation::ReadUncommitted;
        Tablefields.SetRange("Archive ID", Archive."Archive ID");
        Tablefields.SetRange("Table ID", Table."Table ID");
        if Tablefields.FindSet(false) then begin
            RecRef.SetLoadFields(Tablefields."Field ID"); // Set only the first field to load, then add other fields in the loop
            repeat
                // Only query thoses fields to SQL
                Field.Get(Tablefields."Table ID", Tablefields."Field ID");
                RecRef.AddLoadFields(Field."No.");
                // Store field info. in RAM array for faster access
                FieldsCount += 1;
                FieldDataClassifed[FieldsCount] := (Archive.ClassifiedDataHandling <> Archive.ClassifiedDataHandling::Keep)
                                                    and not Tablefields."Part of Primary Key"
                                                    and IsDataClassified(Tablefields."Field DataClassification") and (Tablefields."Field Name".ToLower() in ['name', 'email', 'e-mail', 'mail', 'phone no.', 'fax no.', 'phone', 'mobile phone no.', 'mobile no.', 'birthday', 'birth date', 'address', 'address 1', 'address 2', 'street', 'city', 'post code', 'country', 'family', 'title', 'martial', 'zip', 'zip code']);
                FieldIDList[FieldsCount] := Tablefields."Field ID";
                FieldTypeList[FieldsCount] := Tablefields."Field Type";
                FieldAllEmpty[FieldsCount] := true; // will be set to false at first occurence of none empty data
                if (Tablefields."Field Type" IN [Tablefields."Field Type"::Text, Tablefields."Field Type"::Code, Tablefields."Field Type"::RecordID]) then
                    FieldNeedEscapeList[FieldsCount] := true
                else
                    FieldNeedEscapeList[FieldsCount] := false;
                // Prepare per column blob for transposed Bin (parquet like format)
                if EnableColStore then
                    ColumnOutStrArr[FieldsCount] := ColumnBlobArr[FieldsCount].CreateOutStream();
            until Tablefields.Next() = 0;
            if (FieldsCount = 0) then
                exit;
        end;
        #endregion

        #region Export Records
        if RecRef.FindSet(false) then begin
            // Pre-cache field references and encode flag for hot path
            for I := 1 to FieldsCount do
                FieldRefArr[I] := RecRef.Field(FieldIDList[I]);
            // Create First file chunk
            TableChunkNo := 1;
            CreateChunk(Archive, EnableColStore, Table, TableChunkNo, 0, FieldsCount);
            case EnableColStore of
                true:
                    repeat
                        // Chunk/Progress handling (every 1000 Rec)
                        if (UnCheckedPos >= 1000) then begin
                            TableRecPos += UnCheckedPos;
                            ThreadRecProceed += UnCheckedPos;
                            UnCheckedPos := 0;

                            // Thread progression (Time based)
                            if CurrentDateTime - LastThreadUpdateDT > 1000 then begin
                                UpdateThreadProgress(Thread, Table."Table Name", round(TableRecPos / Table."No. of Records" * 100, 1, '<'), TableRecPos);
                                LastThreadUpdateDT := CurrentDateTime;
                            end;
                            // Chunk Max Size check
                            if CheckChunkMaxSizeForClosure(Archive, FieldsCount, EnableColStore) then begin
                                CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);
                                TableChunkNo += 1;
                                CreateChunk(Archive, EnableColStore, Table, TableChunkNo, TableRecPos, FieldsCount);
                            end;
                        end;

                        // Fields
                        for I := 1 to FieldsCount do
                            if FieldDataClassifed[I] then
                                PipouMgt.WriteBinaryEmptyField(FieldRefArr[I], ColumnOutStrArr[I])
                            else
                                PipouMgt.WriteFieldBinaryData(ColumnOutStrArr[I], FieldAllEmpty[I], FieldRefArr[I]);

                        UnCheckedPos += 1;
                    until RecRef.Next() = 0;
                false:
                    repeat
                        // Chunk/Progress handling (every 1000 Rec)
                        if (UnCheckedPos >= 1000) then begin
                            TableRecPos += UnCheckedPos;
                            ThreadRecProceed += UnCheckedPos;
                            UnCheckedPos := 0;

                            // Thread progression (Time based)
                            if CurrentDateTime - LastThreadUpdateDT > 1000 then begin
                                UpdateThreadProgress(Thread, Table."Table Name", round(TableRecPos / Table."No. of Records" * 100, 1, '<'), TableRecPos);
                                LastThreadUpdateDT := CurrentDateTime;
                            end;
                            // Chunk Max Size check
                            if CheckChunkMaxSizeForClosure(Archive, FieldsCount, EnableColStore) then begin
                                CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);
                                TableChunkNo += 1;
                                CreateChunk(Archive, EnableColStore, Table, TableChunkNo, TableRecPos, FieldsCount);
                            end;
                        end;

                        // Fields
                        for I := 1 to FieldsCount do
                            if FieldDataClassifed[I] then
                                PipouMgt.WriteBinaryEmptyField(FieldRefArr[I], ChunkOutStr)
                            else
                                PipouMgt.WriteFieldBinaryData(ChunkOutStr, FieldAllEmpty[I], FieldRefArr[I]);

                        UnCheckedPos += 1;
                    until RecRef.Next() = 0;
            end;
            TableRecPos += UnCheckedPos;
            ThreadRecProceed += UnCheckedPos;
            #endregion

            // close last chunk
            CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);
        end;
    end;
    #endregion

    local procedure UpdateThreadProgress(var Thread: Record "TOO Pipou Thread"; CurrTableName: Text[30]; CurrTableProgg: Integer; ProceedRecs: Integer)
    begin
        Thread.Status := Thread.Status::"Exporting Data";
        Thread."Current Table" := CurrTableName;
        Thread."Current Table Progress %" := CurrTableProgg;
        Thread."Total Rec. Proceed" := ProceedRecs;
        Thread.Modify();
        Commit();
    end;

    #region Create Chunks
    local procedure CreateChunk(var Archive: Record "TOO Pipou Archive"; EnableTransposition: Boolean; var Table: Record "TOO Pipou Archive Tables"; ChunkNo: Integer; StartIndex: Integer; FieldsCount: Integer)
    var
        I: Integer;
    begin
        clear(ArchiveFile);
        ArchiveFile."Archive Name" := Archive."Archive Name";
        ArchiveFile."Archive ID" := Archive."Archive ID";
        ArchiveFile."Table ID" := Table."Table ID";
        ArchiveFile."Table Name" := Table."Table Name".Replace(' ', '_').Replace('.', '_').Replace('/', '_').Replace('\', '_').Replace('-', '_');
        ArchiveFile."File Name" := ArchiveFile."Table Name" + '_' + format(ChunkNo);
        ArchiveFile."Start Index" := StartIndex;
        ArchiveFile."Chunk No." := ChunkNo;
        if not EnableTransposition then
            TempBlobChunk.CreateOutStream(ChunkOutStr)
        else
            // Reinitialize columns blob
            if (ChunkNo > 1) then begin
                for I := 1 to FieldsCount do
                    ColumnOutStrArr[I] := ColumnBlobArr[I].CreateOutStream();
            end;
    end;
    #endregion

    #region Close Chunks
    local procedure CheckChunkMaxSizeForClosure(var Archive: Record "TOO Pipou Archive"; FieldsCount: Integer; EnableColStore: Boolean): Boolean
    var
        CurrFileSize: Integer;
        I: Integer;
    begin
        if EnableColStore then begin
            CurrFileSize := 0;
            for I := 1 to FieldsCount do
                CurrFileSize += ColumnBlobArr[I].Length();
        end else
            CurrFileSize := TempBlobChunk.Length();

        exit(CurrFileSize > Archive."Chunk Max Size");
    end;

    local procedure CloseChunk(var Thread: Record "TOO Pipou Thread"; var Archive: Record "TOO Pipou Archive"; EnableTranspose: Boolean; var Table: Record "TOO Pipou Archive Tables"; FieldsCount: Integer; var FieldIDList: array[500] of Integer; FieldAllEmpty: array[500] of Boolean; EndIndex: Integer)
    var
        Tablefields: Record "TOO Pipou Archive Fields";
        InStr: InStream;
        OutStr: OutStream;
        I: Integer;
        AdvCompress: Codeunit "TOO Advanced Compression Mgt.";
        ColStoreMgt: Codeunit "TOO Pipou colstore Mgt.";
        Hash: Codeunit "Cryptography Management";
        HashAlgorithmType: Option MD5,SHA1,SHA256,SHA384,SHA512;
        ColstoreBlob: Codeunit "Temp Blob";
    begin
        // Update thread status
        Thread."Current Table Progress %" := 100;
        Thread."Total Rec. Proceed" := ThreadRecProceed;
        Thread.Status := Thread.Status::"Compressing - Storing";
        Thread.Modify();
        Commit();

        //////// COLUMN ORIENTED STORAGE ////////
        if EnableTranspose then begin

            // Set archive file info
            for I := 1 to FieldsCount do
                if not FieldAllEmpty[I] then
                    ArchiveFile."Uncompressed Length" += ColumnBlobArr[I].Length();
            ArchiveFile."Column Storage" := true;

            ColStoreMgt.CreateColStore();

            // COLSTORE COMPRESSION
            // Write each column
            for I := 1 to FieldsCount do begin
                if not FieldAllEmpty[I] then begin
                    Tablefields.Get(Archive."Archive ID", Table."Table ID", FieldIDList[I]);
                    ColStoreMgt.AddColumn(Archive, ArchiveFile, Tablefields, ColumnBlobArr[I]);
                end;
                clear(ColumnBlobArr[I]);
            end;
            ColStoreMgt.ReadColStore(InStr);
            ArchiveFile.Data.CreateOutStream(OutStr);

            // Hash uncompressed signature for integrity check
            ArchiveFile."Uncompressed MD5 Hash" := Hash.GenerateHash(InStr, HashAlgorithmType::MD5);
            InStr.ResetPosition();

            // Compress whole colstore file
            ArchiveFile."Compression Mode" := DetectBestCompression(Archive, InStr);
            AdvCompress.Compress(InStr, OutStr, ArchiveFile."Compression Mode");

            // Free ram
            clear(ColstoreBlob);
            clear(ColStoreMgt);
        end else
        //////// ROW ORIENTED STORAGE ////////
        begin
            TempBlobChunk.CreateInStream(InStr);
            // Hash uncompressed signature for integrity check
            ArchiveFile."Uncompressed MD5 Hash" := Hash.GenerateHash(InStr, HashAlgorithmType::MD5);
            InStr.ResetPosition();
            // Store blob data
            ArchiveFile."Uncompressed Length" := TempBlobChunk.Length();
            ArchiveFile.Data.CreateOutStream(OutStr);
            ArchiveFile."Compression Mode" := DetectBestCompression(Archive, InStr);
            AdvCompress.Compress(InStr, OutStr, ArchiveFile."Compression Mode");
            // Free ram
            Clear(TempBlobChunk);
        end;

        // Archive file informations
        // File name
        ArchiveFile."File Name" := ArchiveFile."Table Name" + '_' + format(ArchiveFile."Chunk No.");
        if ArchiveFile."Column Storage" then
            ArchiveFile."File Name" += '.colstore';
        case ArchiveFile."Compression Mode" of
            ArchiveFile."Compression Mode"::Gzip:
                ArchiveFile."File Name" += '.gz';
            ArchiveFile."Compression Mode"::Zstandard:
                ArchiveFile."File Name" += '.zst';
            ArchiveFile."Compression Mode"::libbsc:
                ArchiveFile."File Name" += '.bsc';
        end;
        ArchiveFile."End Index" := EndIndex;
        ArchiveFile."Number Of Recs" := ArchiveFile."End Index" - ArchiveFile."Start Index";
        ArchiveFile."Compressed Length" := ArchiveFile.Data.Length();
        if ArchiveFile."Compressed Length" = 0 then
            Error('Error while compressing data stream, received empty output result for : File %1, Compression Mode : %2', ArchiveFile."File Name", ArchiveFile."Compression Mode");
        ArchiveFile."Comp. Ratio" := round(100 * (1 - (ArchiveFile."Compressed Length" / ArchiveFile."Uncompressed Length")), 0.01);
        ArchiveFile.Exported := true;
        ArchiveFile.Insert(false);

        // Update meta about empty columns
        I := 1;
        repeat
            if FieldAllEmpty[I] then begin
                Tablefields.Get(Archive."Archive ID", Table."Table ID", FieldIDList[I]);
                Tablefields."Empty In Chunks List" += Format(TableChunkNo) + ',';
                Tablefields.Modify();
            end;
            I += 1;
        until I > FieldsCount;

        // Update thread progression
        Thread."Files Compressed Size (KB)" += ArchiveFile."Compressed Length" / 1024;
        Thread."Files Size (KB)" += ArchiveFile."Uncompressed Length" / 1024;
        Thread.Modify();
        Commit();
    end;
    #endregion

    #region Detect Compression
    procedure DetectBestCompression(var Archive: Record "TOO Pipou Archive"; var InStr: InStream) CompressionMode: Enum "TOO Compression Algo."
    begin
        if InStr.Length() < 1024 then
            // Bellow < 1 KB : No compresion
            exit(CompressionMode::None)
        else
            if Archive."Prefered Compression Mode" = Archive."Prefered Compression Mode"::"Auto (cloud)" then
                // Auto (Cloud)
                if InStr.Length() < 10240 then
                    exit(CompressionMode::None)
                else
                    exit(CompressionMode::Gzip)
            else
                if Archive."Prefered Compression Mode" <> Archive."Prefered Compression Mode"::"Auto (On-Premise)" then
                    exit(Archive."Prefered Compression Mode")
                else
#if ONPREM
                    // Auto (On-Premise) : 
                    if InStr.Length() < 256 * 1024 then
                        // 1 KB - 256 KB : zStd (faster for small size, avoid exe and IO overhead)
                        exit(CompressionMode::zStandard)
                    else // Above >1 MB : Libbsc
                        if IsLibbscAvailable() then
                            exit(CompressionMode::libbsc)
                        else
                            exit(CompressionMode::zStandard);
#else
                    exit(CompressionMode::Gzip);
#endif
    end;

#if ONPREM
    local procedure IsLibbscAvailable(): Boolean
    var
        BscPath: Text;
    begin
        BscPath := System.ApplicationPath();
        BscPath += 'Add-ins\bsc.exe';
        if Exists(BscPath) then
            exit(true)
        else
            if Exists(System.ApplicationPath() + 'bsc.exe') then
                exit(true)
            else
                exit(false);
    end;

    local procedure IsMCMXAvailable(): Boolean
    var
        BscPath: Text;
    begin
        BscPath := System.ApplicationPath();
        BscPath += 'Add-ins\mcmx.exe';
        if Exists(BscPath) then
            exit(true)
        else
            if Exists(System.ApplicationPath() + 'mcmx.exe') then
                exit(true)
            else
                exit(false);
    end;
#endif
    #endregion



    local procedure IsDataClassified(DataClassif: Option): Boolean
    var
        DataClassifOption: Option CustomerContent,ToBeClassified,EndUserIdentifiableInformation,AccountData,EndUserPseudonymousIdentifiers,OrganizationIdentifiableInformation,SystemMetadata;
    begin
        // Field OptionMembers = CustomerContent,ToBeClassified,EndUserIdentifiableInformation,AccountData,EndUserPseudonymousIdentifiers,OrganizationIdentifiableInformation,SystemMetadata;
        if DataClassif IN [DataClassifOption::CustomerContent, DataClassifOption::EndUserIdentifiableInformation, DataClassifOption::EndUserPseudonymousIdentifiers, DataClassifOption::OrganizationIdentifiableInformation] then
            exit(true)
        else
            exit(false);
    end;

    var
        ColumnBlobArr: array[500] of Codeunit "Temp Blob";
        ColumnOutStrArr: array[500] of OutStream;
        TempBlobChunk: Codeunit "Temp Blob";
        CR: Text[1];
        LF: Text[1];
        PipouMgt: Codeunit "TOO Pipou Mgt.";
        ThreadHelper: Codeunit "TOO Pipou Threads Mgt.";
        ChunkOutStr: OutStream;
        ThreadRecProceed: Integer;
        ArchiveFile: Record "TOO Pipou Archive Files";
        TableChunkNo: Integer;
        LastThreadUpdateDT: DateTime;
        StartDT: DateTime;
}