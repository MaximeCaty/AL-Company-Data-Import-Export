codeunit 51005 "TOO Pipou Export Data"
{
    TableNo = "TOO Pipou Thread";


    #region MultiThrd Exp
    procedure MultiThreadExport(var Archive: Record "TOO Pipou Archive")
    var
        OtherArchive: Record "TOO Pipou Archive";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        Thread: Record "TOO Pipou Thread";
        AllThreadCompleted: Boolean;
        ErrorThrown: Boolean;
        GlobalProgress: Decimal;
        RemProgress: Decimal;
        TotCompSize: Decimal;
        TotFileSize: Decimal;
        Win: Dialog;
        ElapsedTime: Duration;
        RemDuration: Duration;
        ArchTotalRecSize: Integer;
        RecProceed: Integer;
        SessionID: Integer;
        NothingToImportLbl: Label 'There is nothing left to import for selected table. Reset the archive import state to redo the import.';
        Progress: Label 'Exporting Data from company #1####\-\Elapsed time : #2########\ Estimated duration : #3#######\-\Global progression :\#4#########\Records : #6######\Compressed Size (KB) : #7#######-\#8######\-\#9######\-\#10######\-\#11######\-\#12######\-\#13######';
        ErrorCallStack, ErrorMessage : Text;
        ThreadTxt: Text;
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

        // FK dictionaries : eligibility needs the thread assignment above (the gate prices the per-thread build).
        // Planning only - metadata, no parent table is read here. Each thread builds the dictionaries planned on
        // its own tables when it starts, and waits on the ones another thread owns when it first needs them.
        if Archive."Enable Dictionaries" then begin
            Win.Open('Detecting dictionaries candidat...');
            DictRec.DetectDictionariesFields(Archive);
            // Option dictionaries : pure metadata, built and published right here. They need no thread assignment,
            // no parent read and no wait, so nothing above applies to them.
            DictRec.DetectOptionDictionaries(Archive);
            Win.Close();
        end;

        // Calc total rec to export based on selected tables
        ArchiveTables.SetRange("Archive ID", Archive."Archive ID");
        ArchiveTables.CalcSums("No. of Records");
        ArchTotalRecSize := ArchiveTables."No. of Records";
        if ArchTotalRecSize = 0 then
            Error(NothingToImportLbl);

        // Set state to exporting
        Archive."Process Status" := Archive."Process Status"::"⌛ Exporting";
        Archive.Version := PipouMgt.ArchiveFormatVersion(); // tells the import how to read the encoding flags
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
                Sleep(500);

                AllThreadCompleted := true; // false if any thread not completed
                RecProceed := 0;
                TotFileSize := 0;
                TotCompSize := 0;
                SelectLatestVersion();

                // Thread 1 :
                ThreadTxt := ThreadHelper.UpdateThreadUIProgress(1, AllThreadCompleted, ErrorThrown, ErrorMessage, ErrorCallStack, RecProceed, TotFileSize, TotCompSize, Archive);
                Win.Update(8, ThreadTxt);
                if ErrorThrown then
                    ThrowError(Archive, ErrorMessage, ErrorCallStack);

                // Thread 2 :
                if Archive."Number of Threads" > 1 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadUIProgress(2, AllThreadCompleted, ErrorThrown, ErrorMessage, ErrorCallStack, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(9, ThreadTxt);
                    if ErrorThrown then
                        ThrowError(Archive, ErrorMessage, ErrorCallStack);
                end;
                // Thread 3 :
                if Archive."Number of Threads" > 2 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadUIProgress(3, AllThreadCompleted, ErrorThrown, ErrorMessage, ErrorCallStack, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(10, ThreadTxt);
                    if ErrorThrown then
                        ThrowError(Archive, ErrorMessage, ErrorCallStack);
                end;
                // Thread 4 :
                if Archive."Number of Threads" > 3 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadUIProgress(4, AllThreadCompleted, ErrorThrown, ErrorMessage, ErrorCallStack, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(11, ThreadTxt);
                    if ErrorThrown then
                        ThrowError(Archive, ErrorMessage, ErrorCallStack);
                end;
                // Thread 5 :
                if Archive."Number of Threads" > 4 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadUIProgress(5, AllThreadCompleted, ErrorThrown, ErrorMessage, ErrorCallStack, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(12, ThreadTxt);
                    if ErrorThrown then
                        ThrowError(Archive, ErrorMessage, ErrorCallStack);
                end;
                // Thread 6 :
                if Archive."Number of Threads" > 5 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadUIProgress(6, AllThreadCompleted, ErrorThrown, ErrorMessage, ErrorCallStack, RecProceed, TotFileSize, TotCompSize, Archive);
                    Win.Update(13, ThreadTxt);
                    if ErrorThrown then
                        ThrowError(Archive, ErrorMessage, ErrorCallStack);
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

    local procedure ThrowError(var Archive: Record "TOO Pipou Archive"; Msg: Text; ErrorCallStack: Text)
    var
        ActiveSession: Record "Active Session";
        Thread: Record "TOO Pipou Thread";
        ThreadErrLbl: Label '%1\-\CallStack :\%2', Comment = '%1 = error message, %2 = call stack';
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
        Error(ThreadErrLbl, Msg, ErrorCallStack);
    end;
    #endregion

    #region OnRun (Thread)
    trigger OnRun()
    var
        Archive: Record "TOO Pipou Archive";
        ArchFiles: Record "TOO Pipou Archive Files";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        OtherThreads: Record "TOO Pipou Thread";
    begin
        // Everything before the first table, guarded like the export itself : an unguarded error here killed the
        // session outright, and all the foreground could report was the closing comment of the session - a bare
        // platform message, no call stack, nothing pointing at the statement that failed.
        if not PrepareThread(Rec, Archive) then begin
            ReportThreadError(Rec);
            exit;
        end;
        BlobMaxSize := Archive."Blob Max Size";
        OneByte := 1;
        SentinelByte := 255; // byte ordinal sentinel : "the literal follows inline"
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

        // Table range to proceed. Ordered by "Export Order" : the dictionary sources of this thread first, then the
        // tables that depend on no foreign dictionary, then the ones that read a dictionary another thread builds.
        // Nothing ever blocks on a dictionary : a thread that reaches an unbuilt one builds it itself, and the
        // order above only makes that rebuild rare.
        ArchiveTables.ReadIsolation := ArchiveTables.ReadIsolation::ReadUncommitted;
        ArchiveTables.SetCurrentKey("Archive ID", "Affected Thread", "Export Order", "Table ID");
        ArchiveTables.SetRange("Archive ID", Rec."Archive ID");
        if Rec."Thread No." in [0, 1] then
            // Thread 1 or unaffected
            ArchiveTables.SetRange("Affected Thread", 0, Rec."Thread No.")
        else
            // Thread 2+
            ArchiveTables.SetRange("Affected Thread", Rec."Thread No.");


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
                    Rec."Error Message" := CopyStr(GetLastErrorText(), 1, MaxStrLen(Rec."Error Message"));
                    Rec."Error CallStack" := CopyStr(GetLastErrorCallStack(), 1, MaxStrLen(Rec."Error CallStack"));
                    Rec.Modify();
                    Commit();
                    exit;
                end;
                // A table that was supposed to fill its dictionaries inline but ended before its record loop leaves
                // them unbuilt : read here rather than letting another thread wait for something that never comes.
                if InlineDictTables.ContainsKey(ArchiveTables."Table ID") then
                    DictRec.PublishPendingDictionaries(Archive, ArchiveTables."Table ID");
            until ArchiveTables.Next() = 0;

        // All thread completed, update archive + remove threads
        OtherThreads.SetRange("Archive ID", Archive."Archive ID");
        OtherThreads.SetFilter("Thread No.", '<>%1', Rec."Thread No.");
        OtherThreads.SetFilter(Status, '<>%1', OtherThreads.Status::"Completed ✅");
        if OtherThreads.IsEmpty() then begin
            Archive.Get(Archive."Archive Name", Archive."Archive ID");
            Archive."Process Status" := Archive."Process Status"::"✅ Exported";
            if Archive."Process Started At" <> 0DT then
                Archive."Export Duration" := CurrentDateTime - Archive."Process Started At";
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
            Sleep(1000);
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

    [TryFunction]
    local procedure PrepareThread(var Rec: Record "TOO Pipou Thread"; var Archive: Record "TOO Pipou Archive")
    begin
        // Set thread status as started. The record travelled through StartSession as a snapshot taken by the
        // foreground before the session existed : re-read before writing it, a Modify on the snapshot is a write
        // against a row version this session never observed.
        Rec.Get(Rec."Thread No.");
        Rec."Session ID" := SessionId();
        Rec.Status := Rec.Status::"Exporting Data";
        Rec.Modify();
        Commit();

        // Initialize
        Archive.Get(Rec."Archive Name", Rec."Archive ID");
        // Read here and not in OnRun : the gate below is the first use of the flag, and an assignment sitting after
        // this call left it false for the whole build, which silently disabled every dictionary of the archive.
        EnableArchiveDict := Archive."Enable Dictionaries";

        // FK dictionaries : build the ones planned on the tables of this thread, then export straight away. The
        // preparation is split across the threads instead of being a sequential barrier, and a column encoded
        // against a parent owned by another thread waits for that dictionary on its first cell.
        // Most of them are not read here at all : "InlineDictTables" carries the parents whose dictionary is filled
        // from their own export loop below, which is a full read of the parent this thread was going to do anyway.
        if EnableArchiveDict then begin
            Rec.Status := Rec.Status::"Building Dictionaries";
            Rec.Modify();
            Commit();
            DictRec.BuildThreadDictionaries(Archive, Rec."Thread No.", InlineDictTables);
            Rec.Get(Rec."Thread No."); // the build commits, and a foreign thread may have written this row meanwhile
            Rec.Status := Rec.Status::"Exporting Data";
            Rec.Modify();
            Commit();
        end;
    end;

    local procedure ReportThreadError(var Rec: Record "TOO Pipou Thread")
    var
        ErrCallStack: Text;
        ErrText: Text;
    begin
        // Same reporting path as an error raised inside ExportTableData : the log row carries the call stack, the
        // thread row carries the message the foreground dialog reads.
        ErrText := GetLastErrorText();
        ErrCallStack := GetLastErrorCallStack();
        Clear(ArchiveFile);
        ArchiveFile."Archive Name" := Rec."Archive Name";
        ArchiveFile."Archive ID" := Rec."Archive ID";
        ArchiveFile."Affected Thread" := Rec."Thread No.";
        ArchiveFile."File Name" := 'preparing thread...';
        PipouMgt.LogALErrorMessage(ArchiveFile, ErrText, ErrCallStack);
        if Rec.Get(Rec."Thread No.") then begin
            Rec.Status := Rec.Status::"❌ Error";
            Rec."Error Message" := CopyStr(ErrText, 1, MaxStrLen(Rec."Error Message"));
            Rec."Error CallStack" := CopyStr(ErrCallStack, 1, MaxStrLen(Rec."Error CallStack"));
            Rec.Modify();
        end;
        Commit();
    end;
    #endregion

    #region ExportTbleData
    [TryFunction]
    procedure ExportTableData(var Thread: Record "TOO Pipou Thread"; var Archive: Record "TOO Pipou Archive"; var Table: Record "TOO Pipou Archive Tables")
    begin
        // Ignore export of it self
        if Table."Table ID" in [Database::"TOO Pipou Archive Files", Database::"TOO Pipou Archive", Database::"TOO Pipou Import Log", Database::"TOO Pipou Archive Fields", Database::"TOO Pipou Archive Tables", Database::"TOO Pipou Thread"] then
            exit;

        // Open Record
        RecRef.Open(Table."Table ID", false, Archive."Exported From Company");
        if Table."No. of Records" = 0 then
            exit;

        // reset
        TableRecPos := 0;
        UnCheckedPos := 0;
        EnableFieldDict := false;
        EnableOptDict := false;
        EnableColStore := false;
        FieldsCount := 0;
        DictFirstIdx := 0;
        OptFirstIdx := 0;
        OptSlotCount := 0;
        Clear(OptSlotByName);
        InlineDictCount := 0;

        // Enable transposition on 100+ records
        if Archive."Enable Columns Transcoding" then
            EnableColStore := (Table."No. of Records" > 100);

        #region Field definition
        // Store fields ID in array for faster reference
        Clear(PlainFieldIds);
        Clear(PlainClassified);
        Clear(DictFieldIds);
        Clear(DictFileNames);
        Clear(OptFieldIds);
        Clear(OptFileNames);
        Tablefields.ReadIsolation := Tablefields.ReadIsolation::ReadUncommitted;
        Tablefields.SetRange("Archive ID", Archive."Archive ID");
        Tablefields.SetRange("Table ID", Table."Table ID");
        if Tablefields.FindSet(false) then begin
            RecRef.SetLoadFields(Tablefields."Field ID"); // Set only the first field to load, then add other fields in the loop
            // Single pass : the classification test is a ToLower plus a 26 entry string comparison, and it used to
            // run once per grouping pass on every field of every table. Each field is evaluated once here and lands
            // in its group list ; the three loops below only materialize what the hot loop reads.
            repeat
                FieldClassified := PipouMgt.IsFieldAnonymized(Tablefields, Archive.ClassifiedDataHandling);
                // Dictionary : only column oriented files carry ordinals, and a dropped classified column never does.
                // Gated on the archive flag too : the encoding loops below are, so a column left in the dictionary
                // group by a stale "Use Dictionary" flag would be written by no loop at all.
                FieldIsDict := EnableArchiveDict and EnableColStore and Tablefields."Use Dictionary" and not FieldClassified;
                // Option and FK dictionaries never overlap : the FK detection only ever flags Code and Text columns
                FieldIsOptDict := FieldIsDict and (Tablefields."Field Type" = Tablefields."Field Type"::Option);
                if FieldIsOptDict then
                    FieldIsDict := false;
                // Stamp what the column actually gets, not what the detection planned : the import reads the flag
                // instead of replaying these rules, which is what kept the two sides able to disagree.
                if Tablefields."Use Dictionary" <> (FieldIsDict or FieldIsOptDict) then begin
                    StampedFields.Get(Tablefields."Archive ID", Tablefields."Table ID", Tablefields."Field ID");
                    StampedFields."Use Dictionary" := FieldIsDict or FieldIsOptDict;
                    StampedFields.Modify();
                end;
                // Only query thoses fields to SQL
                RecRef.AddLoadFields(Tablefields."Field ID");
                if FieldIsDict then begin
                    DictFieldIds.Add(Tablefields."Field ID");
                    DictFileNames.Add(Tablefields."Dictionary File Name");
                end else
                    if FieldIsOptDict then begin
                        OptFieldIds.Add(Tablefields."Field ID");
                        OptFileNames.Add(Tablefields."Dictionary File Name");
                    end else begin
                        PlainFieldIds.Add(Tablefields."Field ID");
                        PlainClassified.Add(FieldClassified);
                    end;
            until Tablefields.Next() = 0;

            // Plain columns take the low indexes, FK dictionary columns the next ones, option dictionary columns the
            // high ones, so each loop of the hot path stays flat with no per field test at all. Column order is free
            // in column storage, every column carries its Field ID in columns.json and the import resolves it by ID.
            for K := 1 to PlainFieldIds.Count() do begin
                FieldsCount += 1;
                FieldIDList[FieldsCount] := PlainFieldIds.Get(K);
                FieldDataClassifed[FieldsCount] := PlainClassified.Get(K);
                FieldAllEmpty[FieldsCount] := true; // will be set to false at first occurence of none empty data
                DanglingFKCount[FieldsCount] := 0;
                // Prepare per column blob for transposed Bin (parquet like format)
                if EnableColStore then
                    ColumnOutStrArr[FieldsCount] := ColumnBlobArr[FieldsCount].CreateOutStream();
            end;

            DictFirstIdx := FieldsCount + 1; // index of the first FK dictionary encoded column
            for K := 1 to DictFieldIds.Count() do begin
                FieldsCount += 1;
                FieldIDList[FieldsCount] := DictFieldIds.Get(K);
                FieldDataClassifed[FieldsCount] := false; // a classified column never reaches the dictionary group
                FieldAllEmpty[FieldsCount] := true;
                DanglingFKCount[FieldsCount] := 0;
                EnableFieldDict := true;
                // One hashtable per parent, held in a list : the hot loop reaches it by index, so a cell
                // costs one List.Get plus one hash of the bare value, and builds no string at all.
                DictFileName := DictFileNames.Get(K);
                if not DictIdxByName.Get(DictFileName, DictIdx) then begin
                    ExpDictList.Add(DictRec.LoadExportDictionary(Archive, DictFileName, Thread."Thread No."));
                    DictIdx := ExpDictList.Count();
                    // Only a resolved dictionary is cached for the rest of the thread. An empty one is a
                    // dictionary this thread has not filled yet : this table sentinels its column, but the
                    // tables exported after the parent must get the real hashtable, not the empty one.
                    if ExpDictList.Get(DictIdx).Count() > 0 then
                        DictIdxByName.Set(DictFileName, DictIdx);
                end;
                FieldDictIdx[FieldsCount] := DictIdx;
                if EnableColStore then
                    ColumnOutStrArr[FieldsCount] := ColumnBlobArr[FieldsCount].CreateOutStream();
            end;

            OptFirstIdx := FieldsCount + 1; // index of the first option dictionary encoded column
            for K := 1 to OptFieldIds.Count() do begin
                FieldsCount += 1;
                FieldIDList[FieldsCount] := OptFieldIds.Get(K);
                FieldDataClassifed[FieldsCount] := false;
                FieldAllEmpty[FieldsCount] := true;
                DanglingFKCount[FieldsCount] := 0;
                EnableOptDict := true;
                // One slot per distinct dictionary : several columns of the table typed on the same
                // enum share one ordinal array, and the hot loop reaches it by index.
                DictFileName := OptFileNames.Get(K);
                if not OptSlotByName.Get(DictFileName, OptSlotNo) then begin
                    OptSlotNo := 0;
                    if OptSlotCount < ArrayLen(OptOrdinals, 1) then begin
                        OptSlotCount += 1;
                        OptSlotMembers[OptSlotCount] := DictRec.LoadOptionOrdinals(Archive."Archive ID", DictFileName, OptLoad);
                        for J := 1 to OptSlotMembers[OptSlotCount] do
                            OptOrdinals[OptSlotCount, J] := OptLoad[J];
                        OptSlotNo := OptSlotCount;
                        OptSlotByName.Set(DictFileName, OptSlotNo);
                    end;
                end;
                OptSlot[FieldsCount] := OptSlotNo;
                // Slot 0 : past the slot cap, or a dictionary left out of the archive. Every cell then
                // sentinels and carries its real ordinal inline, which the import already decodes.
                if OptSlotNo = 0 then
                    OptCount[FieldsCount] := 0
                else
                    OptCount[FieldsCount] := OptSlotMembers[OptSlotNo];
                if EnableColStore then
                    ColumnOutStrArr[FieldsCount] := ColumnBlobArr[FieldsCount].CreateOutStream();
            end;

            if (FieldsCount = 0) then
                exit;
        end;
        #endregion

        #region Inline FK dictionaries
        // The primary key column a dictionary holds is already read by the export loop below : the dictionaries
        // planned on this table are filled from it, instead of costing a dedicated read of the table before any
        // export starts. Column oriented and full exports only : a differential export reads a filtered subset of
        // the parent, which would leave holes in the ordinals.
        if EnableArchiveDict then begin
            InlineDictCount := 0;
            if InlineDictTables.ContainsKey(Table."Table ID") and EnableColStore then
                if DictRec.GetInlineDictionaries(Archive."Archive ID", Table."Table ID", InlineFileNames, InlineFieldNos, InlineDedup) then begin
                    Clear(InlineValues);
                    InlineDictCount := InlineFileNames.Count();
                    if InlineDictCount > ArrayLen(InlineCapIdx) then
                        InlineDictCount := ArrayLen(InlineCapIdx);
                    InlineColumnMissing := false;
                    for K := 1 to InlineDictCount do begin
                        // A primary key field is never dropped as classified, so it is always in the plain column group
                        InlineCapIdx[K] := 0;
                        for I := 1 to FieldsCount do
                            if FieldIDList[I] = InlineFieldNos.Get(K) then
                                InlineCapIdx[K] := I;
                        if InlineCapIdx[K] = 0 then
                            InlineColumnMissing := true;
                        InlineValues.Add(NewInlineValues()); // fresh instance : AL collections are reference types
                    end;
                    // A planned column that this table does not export : leave the whole table to PublishPendingDictionaries
                    if InlineColumnMissing then
                        InlineDictCount := 0;
                end;
        end;
        #endregion

        #region Export Records
        RecRef.ReadIsolation := RecRef.ReadIsolation::ReadUncommitted;
        if RecRef.FindSet(false) then begin
            // Pre-cache field references for hot path
            for I := 1 to FieldsCount do begin
                FieldRefArr[I] := RecRef.Field(FieldIDList[I]);
                // Type is constant per column : read it once here instead of one FieldRef interop read per record
                FieldRefTypeArr[I] := FieldRefArr[I].Type;
            end;
            // Create First file chunk
            TableChunkNo := 1;
            LastThreadUpdateDT := CurrentDateTime;
            CreateChunk(Archive, EnableColStore, Table, TableChunkNo, 0, FieldsCount);
            case EnableColStore of
                true:
                    if (Archive.ClassifiedDataHandling = Archive.ClassifiedDataHandling::Keep) then
                        #region Col+Keep
                        // COLUMN ORIENTED + KEEP ALL
                        repeat
                            // Chunk/Progress handling (every 500 Rec + every 1s)
                            if (UnCheckedPos >= 1000) then begin
                                TableRecPos += UnCheckedPos;
                                ThreadRecProceed += UnCheckedPos;
                                UnCheckedPos := 0;

                                // Thread progression (Time based)
                                if CurrentDateTime - LastThreadUpdateDT > 1000 then begin
                                    UpdateThreadProgress(Thread, Table."Table Name", Round(TableRecPos / Table."No. of Records" * 100, 1, '<'), ThreadRecProceed);
                                    LastThreadUpdateDT := CurrentDateTime;
                                end;
                                // Chunk Max Size check
                                if CheckChunkMaxSizeForClosure(Archive."Chunk Max Size", FieldsCount, EnableColStore) then begin
                                    // Detect empty text field using shared dict (if only 0 bytes (1 byte per record) = all empty
                                    CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);
                                    TableChunkNo += 1;
                                    CreateChunk(Archive, EnableColStore, Table, TableChunkNo, TableRecPos, FieldsCount);
                                end;
                            end;

                            // Fields
                            // Plain columns only : the FK and option dictionary groups are grouped after them and are
                            // written by the encoding loops below. Running to FieldsCount here wrote the literal value
                            // into those columns first, and the ordinal was then appended to the same stream.
                            for I := 1 to DictFirstIdx - 1 do
                                case FieldRefTypeArr[I] of
                                    FieldType::Option,
                                    FieldType::Integer:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefIntFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Text:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefTextFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Code:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefCodeFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Date:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefDateFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::DateTime:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefDateTimeFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Boolean:
                                        begin
                                            EvalBool := FieldRefArr[I].Value;
                                            if EvalBool then begin
                                                ColumnOutStrArr[I].Write(OneByte);
                                                FieldAllEmpty[I] := false;
                                            end else
                                                ColumnOutStrArr[I].Write(ZeroByte);
                                        end;

                                    FieldType::Decimal:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefDecFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Guid:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if not IsNullGuid(FieldRefArr[I].Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Duration:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefDurFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Time:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefTimeFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::DateFormula:
                                        begin
                                            ColumnOutStrArr[I].Write(Format(FieldRefArr[I].Value, 0, 9));
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefDateFormulaFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::RecordId:

                                        // Must use in try function because uninstalled table ref throw runtime error
                                        if TryFormatRecID(FieldRefArr[I], EvalText) then begin
                                            ColumnOutStrArr[I].Write(EvalText);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefRecIDFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end else
                                            ColumnOutStrArr[I].Write('');

                                    FieldType::Blob:
                                        // 0 byte written = empty blob
                                        if BlobMgt.ExportBlobFieldBinary(FieldRefArr[I], ColumnOutStrArr[I], BlobMaxSize) <> 0 then
                                            FieldAllEmpty[I] := false;

                                    FieldType::Media:
                                        begin
                                            if not (IsNullGuid(FieldRefArr[I].Value)) then begin
                                                BlobMgt.ExportMediaFieldBinary(FieldRefArr[I].Value, ColumnOutStrArr[I]);
                                                FieldAllEmpty[I] := false;
                                            end else
                                                ColumnOutStrArr[I].Write(0);
                                        end;

                                    FieldType::MediaSet:
                                        begin
                                            if not (IsNullGuid(FieldRefArr[I].Value)) then begin
                                                BlobMgt.ExportMediaSetFieldBinary(FieldRefArr[I].Value, ColumnOutStrArr[I]);
                                                FieldAllEmpty[I] := false;
                                            end else
                                                ColumnOutStrArr[I].Write(0);
                                        end;

                                    FieldType::BigInteger:
                                        begin
                                            ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefBigIntFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;
                                    else
                                        Error('Field type unsupported for binary writting : %1', FieldRefTypeArr[I]); // Unknown data type ?
                                end;

                            #region FK dict (Col+Keep)
                            // Dictionary encoded columns are grouped at the end of the index space, so neither loop
                            // pays a per field test.
                            if EnableArchiveDict then begin

                                if EnableFieldDict then
                                    for I := DictFirstIdx to OptFirstIdx - 1 do begin

                                        // Blank is ordinal 0 and must be tested explicitly : most FK columns are mostly
                                        // blank, and no parent holds a blank primary key, so a lookup would sentinel them all.
                                        EvalDictText := FieldRefArr[I].Value;
                                        if EvalDictText = '' then
                                            EvalDictOrd := 0
                                        else begin
                                            // Blanks never touch the list
                                            if not ExpDictList.Get(FieldDictIdx[I]).Get(EvalDictText, EvalDictOrd) then
                                                EvalDictOrd := -1; // dangling FK : BC does not always enforce integrity on historical data
                                                                   // Ordinal or inline literal, the column carries data either way : leaving it
                                                                   // flagged empty would have CloseChunk drop it.
                                            FieldAllEmpty[I] := false;
                                        end;
                                        if EvalDictOrd < 0 then
                                            ColumnOutStrArr[I].Write(SentinelByte)
                                        else begin
                                            EvalDictByte := EvalDictOrd;
                                            ColumnOutStrArr[I].Write(EvalDictByte);
                                        end;

                                        if EvalDictOrd < 0 then begin
                                            ColumnOutStrArr[I].Write(EvalDictText); // sentinel : literal inline
                                            DanglingFKCount[I] += 1;
                                        end;
                                    end;
                                #endregion

                                #region Option dict (Col+Keep)
                                // Enum ordinals packed to a dense byte. The member scan is inlined here on purpose :
                                // a helper call or a hashtable lookup would cross the interop boundary once per cell,
                                // which costs more than walking the handful of members an encoded enum holds.
                                if EnableOptDict then
                                    for I := OptFirstIdx to FieldsCount do begin
                                        EvalOptOrd := FieldRefArr[I].Value;
                                        EvalOptDense := 0;
                                        J := 1;
                                        while J <= OptCount[I] do begin
                                            if OptOrdinals[OptSlot[I], J] = EvalOptOrd then begin
                                                EvalOptDense := J;
                                                J := OptCount[I]; // found : the increment below ends the scan
                                            end;
                                            J += 1;
                                        end;
                                        if EvalOptDense = 0 then begin
                                            // Not a declared member : a value left behind by a removed enum value, or
                                            // a column past the slot cap. Real ordinal inline, same shape as the FK dict.
                                            ColumnOutStrArr[I].Write(SentinelByte);
                                            ColumnOutStrArr[I].Write(EvalOptOrd);
                                        end else begin
                                            EvalOptByte := EvalOptDense - 1;
                                            ColumnOutStrArr[I].Write(EvalOptByte);
                                        end;
                                        // Same empty test as the plain Option column : 0 is the BC default ordinal
                                        if FieldAllEmpty[I] then
                                            if EvalOptOrd <> 0 then
                                                FieldAllEmpty[I] := false;
                                    end;
                                #endregion

                                #region Inline dict capture (Col+Keep)
                                // Primary key order is the contract between export and import : this loop reads the
                                // parent in that order, so the ordinals come out exactly as a dedicated read would.
                                if InlineDictCount > 0 then
                                    for K := 1 to InlineDictCount do begin
                                        EvalDictText := FieldRefArr[InlineCapIdx[K]].Value;
                                        // A primary key column that is not the whole key repeats : only the distinct
                                        // values are kept, the ordinals still come out of the stream. Linear Contains
                                        // rather than a seen-set : a dictionary parent is capped at 253 rows.
                                        if InlineDedup then begin
                                            if (EvalDictText <> '') and not InlineValues.Get(K).Contains(EvalDictText) then
                                                InlineValues.Get(K).Add(EvalDictText);
                                        end else
                                            InlineValues.Get(K).Add(EvalDictText);
                                    end;
                            end;
                            #endregion

                            UnCheckedPos += 1;
                        until RecRef.Next() = 0
                    #endregion
                    else
                        #region Col+NotClass
                        // COLUMN ORIENTED + NOT CLASSIFIED
                        repeat
                            // Chunk/Progress handling (every 1000 Rec + every 1s)
                            if (UnCheckedPos >= 1000) then begin
                                TableRecPos += UnCheckedPos;
                                ThreadRecProceed += UnCheckedPos;
                                UnCheckedPos := 0;

                                // Thread progression (Time based)
                                if CurrentDateTime - LastThreadUpdateDT > 1000 then begin
                                    UpdateThreadProgress(Thread, Table."Table Name", Round(TableRecPos / Table."No. of Records" * 100, 1, '<'), ThreadRecProceed);
                                    LastThreadUpdateDT := CurrentDateTime;
                                end;
                                // Chunk Max Size check
                                if CheckChunkMaxSizeForClosure(Archive."Chunk Max Size", FieldsCount, EnableColStore) then begin
                                    CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);
                                    TableChunkNo += 1;
                                    CreateChunk(Archive, EnableColStore, Table, TableChunkNo, TableRecPos, FieldsCount);
                                end;
                            end;

                            // Fields
                            // Plain columns only : same grouping as the Col+Keep branch, the dictionary columns are
                            // written by the encoding loops below and must not be written literally here first.
                            for I := 1 to DictFirstIdx - 1 do
                                // Classified columns are a minority : keep the call there, inline only the value path
                                if FieldDataClassifed[I] then
                                    WriteBinaryEmptyField(FieldRefTypeArr[I], ColumnOutStrArr[I]) // in hot loop but unpoplar field - keep local procedure for readability
                                else
                                    case FieldRefTypeArr[I] of
                                        FieldType::Option,
                                        FieldType::Integer:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefIntFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Text:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefTextFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Code:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefCodeFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Date:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefDateFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::DateTime:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefDateTimeFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Boolean:
                                            begin
                                                EvalBool := FieldRefArr[I].Value;
                                                if EvalBool then begin
                                                    ColumnOutStrArr[I].Write(OneByte);
                                                    FieldAllEmpty[I] := false;
                                                end else
                                                    ColumnOutStrArr[I].Write(ZeroByte);
                                            end;

                                        FieldType::Decimal:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefDecFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Guid:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if not IsNullGuid(FieldRefArr[I].Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Duration:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefDurFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Time:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefTimeFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::DateFormula:
                                            begin
                                                ColumnOutStrArr[I].Write(Format(FieldRefArr[I].Value, 0, 9));
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefDateFormulaFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::RecordId:

                                            // Must use in try function because uninstalled table ref throw runtime error
                                            if TryFormatRecID(FieldRefArr[I], EvalText) then begin
                                                ColumnOutStrArr[I].Write(EvalText);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefRecIDFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end else
                                                ColumnOutStrArr[I].Write('');

                                        FieldType::Blob:
                                            // 0 byte written = empty blob
                                            if BlobMgt.ExportBlobFieldBinary(FieldRefArr[I], ColumnOutStrArr[I], BlobMaxSize) <> 0 then
                                                FieldAllEmpty[I] := false;

                                        FieldType::Media:
                                            begin
                                                if not (IsNullGuid(FieldRefArr[I].Value)) then begin
                                                    BlobMgt.ExportMediaFieldBinary(FieldRefArr[I].Value, ColumnOutStrArr[I]);
                                                    FieldAllEmpty[I] := false;
                                                end else
                                                    ColumnOutStrArr[I].Write(0);
                                            end;

                                        FieldType::MediaSet:
                                            begin
                                                if not (IsNullGuid(FieldRefArr[I].Value)) then begin
                                                    BlobMgt.ExportMediaSetFieldBinary(FieldRefArr[I].Value, ColumnOutStrArr[I]);
                                                    FieldAllEmpty[I] := false;
                                                end else
                                                    ColumnOutStrArr[I].Write(0);
                                            end;

                                        FieldType::BigInteger:
                                            begin
                                                ColumnOutStrArr[I].Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefBigIntFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;
                                        else
                                            Error('Field type unsupported for binary writting : %1', FieldRefTypeArr[I]); // Unknown data type ?
                                    end;

                            #region FK dict (Col+NotClass)
                            // Same encoding as the Col+Keep branch above. A dictionary column is never a dropped
                            // classified column, so this loop needs no classification test either.
                            if EnableArchiveDict then begin
                                if EnableFieldDict then
                                    for I := DictFirstIdx to OptFirstIdx - 1 do begin
                                        EvalDictText := FieldRefArr[I].Value;
                                        if EvalDictText = '' then
                                            EvalDictOrd := 0 // blank : ordinal 0, never looked up
                                        else begin
                                            if not ExpDictList.Get(FieldDictIdx[I]).Get(EvalDictText, EvalDictOrd) then
                                                EvalDictOrd := -1; // dangling FK
                                            FieldAllEmpty[I] := false; // ordinal or inline literal : the column is not empty
                                        end;
                                        if EvalDictOrd < 0 then
                                            ColumnOutStrArr[I].Write(SentinelByte)
                                        else begin
                                            EvalDictByte := EvalDictOrd;
                                            ColumnOutStrArr[I].Write(EvalDictByte);
                                        end;

                                        if EvalDictOrd < 0 then begin
                                            ColumnOutStrArr[I].Write(EvalDictText); // sentinel : literal inline
                                            DanglingFKCount[I] += 1;
                                        end;
                                    end;
                                #endregion

                                #region Option dict (Col+NotClass)
                                // Same encoding as the Col+Keep branch above. An option dictionary column is never a
                                // dropped classified column, so this loop needs no classification test either.
                                if EnableOptDict then
                                    for I := OptFirstIdx to FieldsCount do begin
                                        EvalOptOrd := FieldRefArr[I].Value;
                                        EvalOptDense := 0;
                                        J := 1;
                                        while J <= OptCount[I] do begin
                                            if OptOrdinals[OptSlot[I], J] = EvalOptOrd then begin
                                                EvalOptDense := J;
                                                J := OptCount[I]; // found : the increment below ends the scan
                                            end;
                                            J += 1;
                                        end;
                                        if EvalOptDense = 0 then begin
                                            ColumnOutStrArr[I].Write(SentinelByte);
                                            ColumnOutStrArr[I].Write(EvalOptOrd); // not a declared member : real ordinal inline
                                        end else begin
                                            EvalOptByte := EvalOptDense - 1;
                                            ColumnOutStrArr[I].Write(EvalOptByte);
                                        end;
                                        if FieldAllEmpty[I] then
                                            if EvalOptOrd <> 0 then
                                                FieldAllEmpty[I] := false;
                                    end;
                                #endregion

                                #region Inline dict capture (Col+NotClass)
                                // Same capture as the Col+Keep branch : a primary key column is never a dropped
                                // classified column, so the values here are the real ones either way.
                                if InlineDictCount > 0 then
                                    for K := 1 to InlineDictCount do begin
                                        EvalDictText := FieldRefArr[InlineCapIdx[K]].Value;
                                        if InlineDedup then begin
                                            if (EvalDictText <> '') and not InlineValues.Get(K).Contains(EvalDictText) then
                                                InlineValues.Get(K).Add(EvalDictText);
                                        end else
                                            InlineValues.Get(K).Add(EvalDictText);
                                    end;
                            end;
                            #endregion

                            UnCheckedPos += 1;
                        until RecRef.Next() = 0;
                #endregion
                false:
                    #region Row+Keep
                    // ROW ORIENTED + KEEP ALL
                    if (Archive.ClassifiedDataHandling = Archive.ClassifiedDataHandling::Keep) then
                        repeat
                            // Chunk/Progress handling (every 1000 Rec + every 1s)
                            if (UnCheckedPos >= 1000) then begin
                                TableRecPos += UnCheckedPos;
                                ThreadRecProceed += UnCheckedPos;
                                UnCheckedPos := 0;

                                // Thread progression (Time based)
                                if CurrentDateTime - LastThreadUpdateDT > 1000 then begin
                                    UpdateThreadProgress(Thread, Table."Table Name", Round(TableRecPos / Table."No. of Records" * 100, 1, '<'), ThreadRecProceed);
                                    LastThreadUpdateDT := CurrentDateTime;
                                end;
                                // Chunk Max Size check
                                if CheckChunkMaxSizeForClosure(Archive."Chunk Max Size", FieldsCount, EnableColStore) then begin
                                    CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);
                                    TableChunkNo += 1;
                                    CreateChunk(Archive, EnableColStore, Table, TableChunkNo, TableRecPos, FieldsCount);
                                end;
                            end;

                            // Fields
                            for I := 1 to FieldsCount do
                                case FieldRefTypeArr[I] of
                                    FieldType::Option,
                                    FieldType::Integer:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefIntFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Text:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefTextFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Code:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefCodeFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Date:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefDateFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::DateTime:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefDateTimeFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Boolean:
                                        begin
                                            EvalBool := FieldRefArr[I].Value;
                                            if EvalBool then begin
                                                ChunkOutStr.Write(OneByte);
                                                FieldAllEmpty[I] := false;
                                            end else
                                                ChunkOutStr.Write(ZeroByte);
                                        end;

                                    FieldType::Decimal:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefDecFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Guid:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if not IsNullGuid(FieldRefArr[I].Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Duration:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefDurFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::Time:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefTimeFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::DateFormula:
                                        begin
                                            ChunkOutStr.Write(Format(FieldRefArr[I].Value, 0, 9));
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefDateFormulaFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::RecordId:

                                        // Must use in try function because uninstalled table ref throw runtime error
                                        if TryFormatRecID(FieldRefArr[I], EvalText) then begin
                                            ChunkOutStr.Write(EvalText);
                                            if FieldAllEmpty[I] then
                                                if FieldRefArr[I].Value <> DefRecIDFieldRef.Value then
                                                    FieldAllEmpty[I] := false;
                                        end else
                                            ChunkOutStr.Write('');

                                    FieldType::Blob:
                                        // 0 byte written = empty blob
                                        if BlobMgt.ExportBlobFieldBinary(FieldRefArr[I], ChunkOutStr, BlobMaxSize) <> 0 then
                                            FieldAllEmpty[I] := false;

                                    FieldType::Media:
                                        begin
                                            BlobMgt.ExportMediaFieldBinary(FieldRefArr[I].Value, ChunkOutStr);
                                            if FieldAllEmpty[I] then
                                                if not (IsNullGuid(FieldRefArr[I].Value)) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::MediaSet:
                                        begin
                                            BlobMgt.ExportMediaSetFieldBinary(FieldRefArr[I].Value, ChunkOutStr);
                                            if FieldAllEmpty[I] then
                                                if not IsNullGuid(FieldRefArr[I].Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;

                                    FieldType::BigInteger:
                                        begin
                                            ChunkOutStr.Write(FieldRefArr[I].Value);
                                            if FieldAllEmpty[I] then
                                                if (FieldRefArr[I].Value <> DefBigIntFieldRef.Value) then
                                                    FieldAllEmpty[I] := false;
                                        end;
                                    else
                                        Error('Field type unsupported for binary writting : %1', FieldRefTypeArr[I]); // Unknown data type ?
                                end;
                            //if not WriteFieldBinaryData(ChunkOutStr, FieldRefArr[I], FieldRefTypeArr[I]) then
                            //    FieldAllEmpty[I] := false;

                            UnCheckedPos += 1;
                        until RecRef.Next() = 0
                    #endregion
                    else
                        #region Row+Drop
                        // ROW ORIENTED + NOT CLASSIFIED
                        repeat
                            // Chunk/Progress handling (every 1000 Rec + every 1s)
                            if (UnCheckedPos >= 1000) then begin
                                TableRecPos += UnCheckedPos;
                                ThreadRecProceed += UnCheckedPos;
                                UnCheckedPos := 0;

                                // Thread progression (Time based)
                                if CurrentDateTime - LastThreadUpdateDT > 1000 then begin
                                    UpdateThreadProgress(Thread, Table."Table Name", Round(TableRecPos / Table."No. of Records" * 100, 1, '<'), ThreadRecProceed);
                                    LastThreadUpdateDT := CurrentDateTime;
                                end;
                                // Chunk Max Size check
                                if CheckChunkMaxSizeForClosure(Archive."Chunk Max Size", FieldsCount, EnableColStore) then begin
                                    CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);
                                    TableChunkNo += 1;
                                    CreateChunk(Archive, EnableColStore, Table, TableChunkNo, TableRecPos, FieldsCount);
                                end;
                            end;

                            // Fields
                            for I := 1 to FieldsCount do
                                // Classified columns are a minority : keep the call there, inline only the value path
                                if FieldDataClassifed[I] then
                                    WriteBinaryEmptyField(FieldRefTypeArr[I], ChunkOutStr) // in hot loop but unpoplar field - keep local procedure for readability
                                else
                                    case FieldRefTypeArr[I] of
                                        FieldType::Option,
                                        FieldType::Integer:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefIntFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Text:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefTextFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Code:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefCodeFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Date:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefDateFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::DateTime:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefDateTimeFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Boolean:
                                            begin
                                                EvalBool := FieldRefArr[I].Value;
                                                if EvalBool then begin
                                                    ChunkOutStr.Write(OneByte);
                                                    FieldAllEmpty[I] := false;
                                                end else
                                                    ChunkOutStr.Write(ZeroByte);
                                            end;

                                        FieldType::Decimal:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefDecFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Guid:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if not IsNullGuid(FieldRefArr[I].Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Duration:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefDurFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::Time:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefTimeFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::DateFormula:
                                            begin
                                                ChunkOutStr.Write(Format(FieldRefArr[I].Value, 0, 9));
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefDateFormulaFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::RecordId:

                                            // Must use in try function because uninstalled table ref throw runtime error
                                            if TryFormatRecID(FieldRefArr[I], EvalText) then begin
                                                ChunkOutStr.Write(EvalText);
                                                if FieldAllEmpty[I] then
                                                    if FieldRefArr[I].Value <> DefRecIDFieldRef.Value then
                                                        FieldAllEmpty[I] := false;
                                            end else
                                                ChunkOutStr.Write('');

                                        FieldType::Blob:
                                            // 0 byte written = empty blob
                                            if BlobMgt.ExportBlobFieldBinary(FieldRefArr[I], ChunkOutStr, BlobMaxSize) <> 0 then
                                                FieldAllEmpty[I] := false;

                                        FieldType::Media:
                                            begin
                                                BlobMgt.ExportMediaFieldBinary(FieldRefArr[I].Value, ChunkOutStr);
                                                if FieldAllEmpty[I] then
                                                    if not IsNullGuid(FieldRefArr[I].Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::MediaSet:
                                            begin
                                                BlobMgt.ExportMediaSetFieldBinary(FieldRefArr[I].Value, ChunkOutStr);
                                                if FieldAllEmpty[I] then
                                                    if not IsNullGuid(FieldRefArr[I].Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;

                                        FieldType::BigInteger:
                                            begin
                                                ChunkOutStr.Write(FieldRefArr[I].Value);
                                                if FieldAllEmpty[I] then
                                                    if (FieldRefArr[I].Value <> DefBigIntFieldRef.Value) then
                                                        FieldAllEmpty[I] := false;
                                            end;
                                        else
                                            Error('Field type unsupported for binary writting : %1', FieldRefTypeArr[I]); // Unknown data type ?
                                    end;

                            UnCheckedPos += 1;
                        until RecRef.Next() = 0;
            #endregion
            end;
            RecRef.Close();
            TableRecPos += UnCheckedPos;
            ThreadRecProceed += UnCheckedPos;
            #endregion

            // Dictionaries filled by the loop above : published before the last chunk is compressed, so a thread
            // that reaches one of them finds it built instead of rebuilding it itself.
            if InlineDictCount > 0 then
                DictRec.WriteDictionaries(Archive, Table."Table ID", InlineFileNames, InlineValues);

            // close last chunk
            CloseChunk(Thread, Archive, EnableColStore, Table, FieldsCount, FieldIDList, FieldAllEmpty, TableRecPos);

            // Dictionaries this table really used : "FieldAllEmpty" is never reset between chunks, so at this point
            // it still means "blank in the whole table". A column that stayed blank never looked a value up (blank is
            // ordinal 0, written without touching the dictionary), and a dictionary no table marks here is left out
            // of the archive : the import reads nothing for those columns, they are flagged empty in every chunk.
            // FK dictionaries only : an option map is shipped unconditionally (a few KB for the whole archive) and
            // is already marked used when it is created. Marking it here had every thread take a row lock on the
            // same handful of shared "opt$" rows, in the column order of the table it had just finished, which is
            // not the same order on two tables : four threads then deadlocked on each other's option rows.
            for I := DictFirstIdx to OptFirstIdx - 1 do
                if not FieldAllEmpty[I] then begin
                    Tablefields.Get(Archive."Archive ID", Table."Table ID", FieldIDList[I]);
                    DictRec.MarkUsed(Archive."Archive ID", Tablefields."Dictionary File Name");
                end;
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
        Clear(ArchiveFile);
        ArchiveFile."Archive Name" := Archive."Archive Name";
        ArchiveFile."Archive ID" := Archive."Archive ID";
        ArchiveFile."Table ID" := Table."Table ID";
        ArchiveFile."Table Name" := Table."Table Name".Replace(' ', '_').Replace('.', '_').Replace('/', '_').Replace('\', '_').Replace('-', '_');
        ArchiveFile."File Name" := ArchiveFile."Table Name" + '_' + Format(ChunkNo);
        ArchiveFile."Start Index" := StartIndex;
        ArchiveFile."Chunk No." := ChunkNo;
        if not EnableTransposition then
            TempBlobChunk.CreateOutStream(ChunkOutStr)
        else
            // Reinitialize columns blob
            if (ChunkNo > 1) then
                for I := 1 to FieldsCount do
                    ColumnOutStrArr[I] := ColumnBlobArr[I].CreateOutStream();
    end;
    #endregion

    #region Close Chunks
    local procedure CheckChunkMaxSizeForClosure(var ChunkMaxSize: Integer; FieldsCount: Integer; EnableColStore: Boolean): Boolean
    var
        CurrFileSize, I : Integer;
    begin
        if EnableColStore then
            for I := 1 to FieldsCount do
                CurrFileSize += ColumnBlobArr[I].Length()
        else
            CurrFileSize := TempBlobChunk.Length();

        exit(CurrFileSize > ChunkMaxSize);
    end;

    local procedure CloseChunk(var Thread: Record "TOO Pipou Thread"; var Archive: Record "TOO Pipou Archive"; EnableTranspose: Boolean; var Table: Record "TOO Pipou Archive Tables"; FieldsCount: Integer; var FieldIDList: array[500] of Integer; FieldAllEmpty: array[500] of Boolean; EndIndex: Integer)
    var
        Tablefields: Record "TOO Pipou Archive Fields";
        Hash: Codeunit "Cryptography Management";
        ColstoreBlob: Codeunit "Temp Blob";
        AdvCompress: Codeunit "TOO Advanced Compression Mgt.";
        ColStoreMgt: Codeunit "TOO Pipou colstore Mgt.";
        InStr: InStream;
        I: Integer;
        HashAlgorithmType: Option MD5,SHA1,SHA256,SHA384,SHA512;
        OutStr: OutStream;
    begin
        // Update thread status
        if Table."No. of Records" > 100 then begin
            Thread."Current Table Progress %" := Round(TableRecPos / Table."No. of Records" * 100, 1, '<');
            Thread."Total Rec. Proceed" := ThreadRecProceed;
            Thread.Status := Thread.Status::"Compressing - Storing";
            Thread.Modify();
            Commit();
        end;

        //////// COLUMN ORIENTED STORAGE ////////
        if EnableTranspose then begin

            ArchiveFile."Column Storage" := true;
            ColStoreMgt.CreateColStore();

            // Write each column
            for I := 1 to FieldsCount do begin
                if not FieldAllEmpty[I] then begin
                    Tablefields.Get(Archive."Archive ID", Table."Table ID", FieldIDList[I]);
                    ColStoreMgt.AddColumn(Archive, ArchiveFile, Tablefields, ColumnBlobArr[I]);
                end;
                Clear(ColumnBlobArr[I]); // free RAM gradualy
            end;

            // Create the file
            ColStoreMgt.WriteColstoreTo(InStr);

            // Uncompressed signature for integrity check
            ArchiveFile."Uncompressed MD5 Hash" := Hash.GenerateHash(InStr, HashAlgorithmType::MD5);
            InStr.ResetPosition();
            ArchiveFile."Uncompressed Length" := InStr.Length();

            // Compress whole colstore file
            ArchiveFile."Compression Mode" := DetectBestCompression(Archive, InStr);
            ArchiveFile.Data.CreateOutStream(OutStr);
            AdvCompress.Compress(InStr, OutStr, ArchiveFile."Compression Mode", Archive."Compression Level");

            // Free ram
            Clear(ColstoreBlob);
            Clear(ColStoreMgt);
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
            AdvCompress.Compress(InStr, OutStr, ArchiveFile."Compression Mode", Archive."Compression Level");
            // Free ram
            Clear(TempBlobChunk);
        end;

        // Archive file informations
        // File name
        ArchiveFile."File Name" := ArchiveFile."Table Name" + '_' + Format(ArchiveFile."Chunk No.");
        if ArchiveFile."Column Storage" then
            ArchiveFile."File Name" += '.colstore';
        case ArchiveFile."Compression Mode" of
            ArchiveFile."Compression Mode"::Gzip:
                ArchiveFile."File Name" += '.gz';
            ArchiveFile."Compression Mode"::zStandard:
                ArchiveFile."File Name" += '.zst';
            ArchiveFile."Compression Mode"::libbsc:
                ArchiveFile."File Name" += '.bsc';
            ArchiveFile."Compression Mode"::kanzi:
                ArchiveFile."File Name" += '.knz';
        end;
        ArchiveFile."End Index" := EndIndex;
        ArchiveFile."Number Of Recs" := ArchiveFile."End Index" - ArchiveFile."Start Index";
        ArchiveFile."Compressed Length" := ArchiveFile.Data.Length();
        if ArchiveFile."Compressed Length" = 0 then
            Error('Error while compressing data stream, received empty result for : File %1, Compression Mode : %2', ArchiveFile."File Name", ArchiveFile."Compression Mode");
        ArchiveFile."Comp. Ratio" := Round(100 * (1 - (ArchiveFile."Compressed Length" / ArchiveFile."Uncompressed Length")), 0.01);
        ArchiveFile.Exported := true;
        ArchiveFile.Insert(false);

        // Update meta about empty columns
        for I := 1 to FieldsCount do
            if FieldAllEmpty[I] then begin
                Tablefields.Get(Archive."Archive ID", Table."Table ID", FieldIDList[I]);
                Tablefields."Empty In Chunks List" += Format(TableChunkNo) + ',';
                Tablefields.Modify();
            end;

        // Update thread progression
        Thread."Files Compressed Size (KB)" += ArchiveFile."Compressed Length" / 1024;
        Thread."Files Size (KB)" += ArchiveFile."Uncompressed Length" / 1024;
        Thread.Modify();
        Commit();
    end;
    #endregion

    #region Detect Compr
    procedure DetectBestCompression(var Archive: Record "TOO Pipou Archive"; var InStr: InStream) CompressionMode: Enum "TOO Compression Algo."
    begin
        if InStr.Length() < 1024 then
            // Bellow < 1 KB : No compresion
            exit(CompressionMode::None)
        else
            if Archive."Prefered Compression Mode" = Archive."Prefered Compression Mode"::"Auto (Cloud)" then
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
                        // 1 KB - 256 KB : zStd (faster for small size, avoid IO overhead)
                        exit(CompressionMode::zStandard)
                    else
                        // Above 256 KB : Extreme uses kanzi, Medium and High use libbsc, zStd last fallback
                        if (Archive."Compression Level" = Archive."Compression Level"::Extreme) and IsExeAvailable('kanzi.exe') then
                            exit(CompressionMode::kanzi)
                        else
                            if IsExeAvailable('bsc.exe') then
                                exit(CompressionMode::libbsc)
                            else
                                exit(CompressionMode::zStandard);
#else
                    exit(CompressionMode::Gzip);
#endif
    end;

    [TryFunction]
    local procedure TryFormatRecID(var FieldRefRecID: FieldRef; var Formatted: Text)
    begin
        // "var" is not optional here : without it the caller always wrote an empty RecordId
        Formatted := Format(FieldRefRecID.Value, 0, 9);
    end;

#if ONPREM
    local procedure IsExeAvailable(ExeName: Text): Boolean
    begin
        exit(Exists(System.ApplicationPath() + 'Add-ins\' + ExeName) or Exists(System.ApplicationPath() + ExeName));
    end;
#endif
    #endregion

    #region Write Empty
    procedure WriteBinaryEmptyField(FldType: FieldType; var OutStr: OutStream)
    begin
        // FldType is the cached FieldRef.Type of that column : constant per column, avoids one FieldRef interop read per record
        case FldType of
            FldType::Text,
            FldType::Code,
            FldType::DateFormula,
            FldType::RecordId:
                OutStr.Write('');

            FldType::Blob,
            FldType::MediaSet,
            FldType::Media:
                OutStr.Write(0);

            FldType::Integer,
            FldType::Option:
                OutStr.Write(0);

            FldType::BigInteger,
            FldType::Duration:
                OutStr.Write(0L);

            FldType::Date:
                OutStr.Write(0);

            FldType::Time:
                OutStr.Write(0);

            FldType::DateTime:
                OutStr.Write(0L);

            FldType::Boolean:
                OutStr.Write(ZeroByte);

            FldType::Decimal:
                OutStr.Write(EmptyDecimal); // 12 bits

            FldType::Guid:
                OutStr.Write(EmptyGuid); // 16 bits
            else
                Error('Field type %1 is not supported for empty binary writting', FldType); // Unknown data type ?
        end;
    end;
    #endregion



    local procedure NewInlineValues(): List of [Text]
    begin
    end;

    var // ExportTableData variables - 15% faster access via globals
        Tablefields: Record "TOO Pipou Archive Fields";
        StampedFields: Record "TOO Pipou Archive Fields"; // written copy : Tablefields is the unlocked read of the grouping loop
        RecRef: RecordRef;
        FieldRefArr: array[500] of FieldRef;
        EnableColStore: Boolean;
        EnableFieldDict: Boolean;
        EnableOptDict: Boolean;
        FieldAllEmpty: array[500] of Boolean;
        FieldClassified: Boolean;
        FieldDataClassifed: array[500] of Boolean;
        FieldIsDict: Boolean;
        FieldIsOptDict: Boolean;
        FieldRefTypeArr: array[500] of FieldType;
        DictFirstIdx: Integer; // first index of the FK dictionary encoded columns, they are grouped after the plain ones
        DictIdx: Integer;
        FieldIDList: array[500] of Integer;
        FieldsCount: Integer;
        I: Integer;
        J: Integer;
        OptFirstIdx: Integer; // first index of the option dictionary encoded columns, they are grouped at the end
        TableRecPos: Integer;
        // Field plan, filled by the single pass over the field list and consumed by the three grouping loops
        PlainClassified: List of [Boolean];
        DictFieldIds, OptFieldIds, PlainFieldIds : List of [Integer];
        DictFileNames, OptFileNames : List of [Text];
        DictFileName: Text;
        UnCheckedPos: Integer;
    // ----------------------------

    var
        DictRec: Record "TOO Pipou Archive Dict.";
        ArchiveFile: Record "TOO Pipou Archive Files";
        ColumnBlobArr: array[500] of Codeunit "Temp Blob";
        TempBlobChunk: Codeunit "Temp Blob";
        BlobMgt: Codeunit "TOO Pipou Blob Mgt.";
        PipouMgt: Codeunit "TOO Pipou Mgt.";
        ThreadHelper: Codeunit "TOO Pipou Threads Mgt.";
        AllALTypes: RecordRef;
        DefBigIntFieldRef, DefCodeFieldRef, DefDateFieldRef, DefDateFormulaFieldRef, DefDateTimeFieldRef, DefDecFieldRef, DefDurFieldRef, DefIntFieldRef, DefRecIDFieldRef, DefTextFieldRef, DefTimeFieldRef : FieldRef;
        EvalBool: Boolean;
        InlineColumnMissing: Boolean;
        InlineDedup: Boolean;
        EnableArchiveDict: Boolean;
        EvalDictByte, OneByte, SentinelByte, ZeroByte : Byte;
        EvalOptByte: Byte;
        LastThreadUpdateDT: DateTime;
        StartDT: DateTime;
        EmptyDecimal: Decimal;
        // FK dictionaries filled by the export loop of their own parent : no dedicated read of the parent at all
        InlineDictTables: Dictionary of [Integer, Boolean]; // tables of this thread that carry that job
        DictIdxByName: Dictionary of [Text, Integer];
        OptSlotByName: Dictionary of [Text, Integer]; // dictionary file name -> its slot, one slot per distinct enum
        EmptyGuid: Guid;
        BlobMaxSize: Integer;
        DanglingFKCount: array[1024] of Integer; // sentinel writes per column, reported per field so a bad relation is identifiable
        EvalDictOrd: Integer;
        EvalOptDense: Integer;
        EvalOptOrd: Integer;
        // dictionary file name -> its index in ExpDictList        FieldDictByte: array[1024] of Boolean;
        FieldDictIdx: array[1024] of Integer;
        InlineCapIdx: array[100] of Integer;  // index in FieldRefArr of the primary key column each dictionary holds
        InlineDictCount: Integer;
        K: Integer;
        OptCount: array[1024] of Integer; // column -> member count, the scan bound
        OptLoad: array[255] of Integer;         // load buffer, copied into the slot row
        // Option dictionary encoding : real member ordinals in a flat array per distinct enum of the table, and the
        // hot loop scans it inlined. No List, no hashtable : both would cost an interop crossing per cell.
        OptOrdinals: array[64, 255] of Integer; // slot -> dense index -> real ordinal
        OptSlot: array[1024] of Integer;  // column -> slot, 0 = not encoded, every cell sentinels
        OptSlotCount: Integer;
        OptSlotMembers: array[64] of Integer;   // member count per slot
        OptSlotNo: Integer;
        TableChunkNo: Integer;
        ThreadRecProceed: Integer;
        // FK dictionary encoding : one hashtable for every parent, per column state in flat arrays
        ExpDictList: List of [Dictionary of [Text, Integer]]; // one hashtable per parent, reached by index from the hot loop
        InlineFieldNos: List of [Integer];
        InlineValues: List of [List of [Text]];             // one value list per dictionary of the table being exported
        InlineFileNames: List of [Text];
        ChunkOutStr: OutStream;
        ColumnOutStrArr: array[512] of OutStream;
        EvalDictText, EvalText : Text;
        CR: Text[1];
        LF: Text[1];
}