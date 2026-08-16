codeunit 51015 "TOO Pipou Threads Mgt."
{

    #region Export Thread
    procedure CreateExportThreads(var Archive: Record "TOO Pipou Archive")
    var
        ArchiveTables: Record "TOO Pipou Archive Tables";
        Threads: Record "TOO Pipou Thread";
        FieldCount: Dictionary of [Integer, Integer];
        I: Integer;
        MinSum: Integer;
        MinThread: Integer;
        ThreadTotalRecSize: array[6] of Integer;
        ThreadWeight: array[6] of Integer;
    begin
        // Create thread information record and split table range across threads
        Threads.DeleteAll();

        // Split threads
        // Loop through table in decreasing size order for better splitting
        ArchiveTables.ReadIsolation := ArchiveTables.ReadIsolation::ReadUncommitted;
        ArchiveTables.SetRange("Archive ID", Archive."Archive ID");

        if Archive."Number of Threads" = 1 then begin
            // Single thread
            Threads.Init();
            Threads."Thread No." := 1;
            Threads."Archive ID" := Archive."Archive ID";
            Threads."Archive Name" := Archive."Archive Name";
            ArchiveTables.FindLast();
            Threads."Total Rec. To Process" := Archive."Total Records";
            Threads.Insert();
        end else begin
            // Multiple thread
            // Determine data size per thread

            // Init threads
            for I := 1 to Archive."Number of Threads" do begin
                Threads.Init();
                Threads."Thread No." := I;
                Threads."Archive ID" := Archive."Archive ID";
                Threads."Archive Name" := Archive."Archive Name";
                Threads."Total Rec. To Process" := 0;
                Threads.Insert();
            end;

            // Weight the tables before splitting : the cost of a table is its number of values (records * fields),
            // not its record count. A 300 fields table costs 30 times more per record than a 10 fields one.
            BuildFieldCountPerTable(Archive."Archive ID", FieldCount);
            ArchiveTables.FindSet();
            repeat
                ArchiveTables."Thread Weight" := ComputeWeight(ArchiveTables."No. of Records", ArchiveTables."Table ID", FieldCount);
                ArchiveTables.Modify();
            until (ArchiveTables.Next() = 0);

            // Loop tables in decreasing weight order
            ArchiveTables.SetCurrentKey("Archive ID", "Thread Weight");
            ArchiveTables.SetAscending("Thread Weight", false);
            ArchiveTables.FindSet();
            repeat
                // Find thread with smallest current weight
                MinSum := ThreadWeight[1];
                MinThread := 1;
                for I := 2 to Archive."Number of Threads" do
                    if ThreadWeight[I] < MinSum then begin
                        MinSum := ThreadWeight[I];
                        MinThread := I;
                    end;

                ThreadWeight[MinThread] += ArchiveTables."Thread Weight"; // balancing measure

                ThreadTotalRecSize[MinThread] += ArchiveTables."No. of Records"; // UI progress stays counted in records

                ArchiveTables."Affected Thread" := MinThread;
                ArchiveTables.Modify();

            until (ArchiveTables.Next() = 0);

            // Update threads Size
            Threads.Reset();
            if Threads.FindSet(true) then
                repeat
                    Threads."Total Rec. To Process" := ThreadTotalRecSize[Threads."Thread No."];
                    Threads.Modify();
                until Threads.Next() = 0;
        end;
        Commit(); // need to store the thread for sub sessions
    end;
    #endregion

    #region Import Threads
    procedure CreateImportThreads(var Archive: Record "TOO Pipou Archive")
    var
        ArchiveFiles: Record "TOO Pipou Archive Files";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        Threads: Record "TOO Pipou Thread";
        FieldCount: Dictionary of [Integer, Integer];
        I: Integer;
        MinThread: Integer;
        ThreadTotalRecSize: array[6] of Integer;
        ThreadWeight: array[6] of Integer;
    begin
        // Create thread information record and split table range across threads
        Threads.DeleteAll();

        // Split threads
        // Loop through table in decreasing size order for better splitting
        ArchiveFiles.ReadIsolation := ArchiveFiles.ReadIsolation::ReadUncommitted;
        ArchiveFiles.SetRange("Archive ID", Archive."Archive ID");
        ArchiveFiles.ModifyAll("Affected Thread", 0);
        ArchiveFiles.SetRange(Imported, false);
        ArchiveFiles.SetRange("Table Selected For Import", true);
        ArchiveFiles.SetFilter("Matched Table ID", '<>0');
        // Exclude itself
        ArchiveFiles.SetFilter("Table ID", '<>%1&<>%2&<>%3&<>%4&<>%5&<>%6', Database::"TOO Pipou Archive", Database::"TOO Pipou Archive Fields", Database::"TOO Pipou Archive Tables", Database::"TOO Pipou Archive Files", Database::"TOO Pipou Thread", Database::"TOO Temp Blob");

        if Archive."Number of Threads" = 1 then begin
            ArchiveFiles.ModifyAll("Affected Thread", 1);
            // Verify metadata exists
            ArchiveTables.SetRange("Archive ID", Archive."Archive ID");
            ArchiveTables.FindLast();
            // Create single thread
            Threads.Init();
            Threads."Thread No." := 1;
            Threads."Archive ID" := Archive."Archive ID";
            Threads."Archive Name" := Archive."Archive Name";
            Threads."Total Rec. To Process" := Archive."Total Records";
            Threads.Insert();
        end else begin
            // Multiple thread
            // Determine data size per thread

            // Init threads
            for I := 1 to Archive."Number of Threads" do begin
                Threads.Init();
                Threads."Thread No." := I;
                Threads."Archive ID" := Archive."Archive ID";
                Threads."Archive Name" := Archive."Archive Name";
                Threads."Total Rec. To Process" := 0;
                Threads.Insert();
            end;

            // Weight the chunks by number of values (records * fields of their table) instead of record count :
            // a chunk of a 300 fields table costs way more to decode and insert than a chunk of a 10 fields one.
            BuildFieldCountPerTable(Archive."Archive ID", FieldCount);

            // Split per chunk, not per table : a single huge table used to pin one thread while the others idled.
            // Several threads on one table is safe : truncate and index disabling are lock-guarded and done once
            // (see "PreImport Truncated" / "Indexes Disabled" in "TOO Pipou Import Data"), the index rebuild waits
            // for the "Import Completed" flowfield, and the bulk insert drops TABLOCK for row locks when the table
            // is fed by several threads (see TableImportedByMultipleThreads) - measured faster than the table lock.
            // Chunks sorted by decreasing uncompressed size (existing SizeSort key, SQL does the sorting) so the
            // greedy split places the heavy chunks first (LPT).
            ArchiveFiles.SetCurrentKey("Archive ID", "Uncompressed Length");
            ArchiveFiles.SetAscending("Uncompressed Length", false);
            if ArchiveFiles.FindSet(true) then
                repeat
                    MinThread := LightestThread(ThreadWeight, Archive."Number of Threads");
                    ArchiveFiles."Affected Thread" := MinThread;
                    ArchiveFiles.Modify();
                    ThreadWeight[MinThread] += ComputeWeight(ArchiveFiles."Number Of Recs", ArchiveFiles."Table ID", FieldCount); // balancing measure
                    ThreadTotalRecSize[MinThread] += ArchiveFiles."Number Of Recs"; // UI progress stays counted in records
                until ArchiveFiles.Next() = 0;

            // Update threads Size
            Threads.Reset();
            if Threads.FindSet(true) then
                repeat
                    Threads."Total Rec. To Process" := ThreadTotalRecSize[Threads."Thread No."];
                    Threads.Modify();
                until Threads.Next() = 0;
        end;
        Commit(); // need to store the thread for sub sessions
    end;
    #endregion

    #region Thread Weighting
    local procedure LightestThread(var ThreadWeight: array[6] of Integer; NoOfThreads: Integer) MinThread: Integer
    var
        I: Integer;
        MinSum: Integer;
    begin
        MinSum := ThreadWeight[1];
        MinThread := 1;
        for I := 2 to NoOfThreads do
            if ThreadWeight[I] < MinSum then begin
                MinSum := ThreadWeight[I];
                MinThread := I;
            end;
    end;

    local procedure BuildFieldCountPerTable(ArchiveID: Guid; var FieldCount: Dictionary of [Integer, Integer])
    var
        ArchiveFields: Record "TOO Pipou Archive Fields";
        TableFields: Integer;
    begin
        // Single pass over the field metadata instead of one CalcFields per table : the split loops then only do dictionary lookups
        Clear(FieldCount);
        ArchiveFields.ReadIsolation := ArchiveFields.ReadIsolation::ReadUncommitted;
        ArchiveFields.SetRange("Archive ID", ArchiveID);
        ArchiveFields.SetRange("Empty In Chunks List", '');
        ArchiveFields.SetLoadFields("Table ID");
        if ArchiveFields.FindSet() then
            repeat
                if not FieldCount.Get(ArchiveFields."Table ID", TableFields) then
                    TableFields := 0;
                FieldCount.Set(ArchiveFields."Table ID", TableFields + 1);
            until ArchiveFields.Next() = 0;
    end;

    local procedure ComputeWeight(NoOfRecords: Integer; TableID: Integer; var FieldCount: Dictionary of [Integer, Integer]) Weight: Integer
    var
        Values: Decimal;
        NoOfFields: Integer;
    begin
        // Weight = values to process, counted in thousands. Decimal intermediate : records * fields overflows an Integer before the division.
        if not FieldCount.Get(TableID, NoOfFields) then
            NoOfFields := 1; // no field metadata : fall back on the record count alone
        Values := NoOfRecords;
        Weight := Round(Values * NoOfFields / 1000, 1, '>'); // rounded up : a small table must not weigh 0 and pile up on thread 1
    end;
    #endregion

    #region Thread Progression
    procedure UpdateThreadUIProgress(ThreadNo: Integer; var AllThreadCompleted: Boolean; var ErrorThrown: Boolean; var ErrorMsg: Text; var ErrorCallStack: Text; var RecProceed: Integer; var TotFileSize: Decimal; var Archive: Record "TOO Pipou Archive") ThreadTxt: Text

    var
        TotCompSize: Decimal;
    begin
        exit(UpdateThreadUIProgress(ThreadNo, AllThreadCompleted, ErrorThrown, ErrorMsg, ErrorCallStack, RecProceed, TotFileSize, TotCompSize, Archive));
    end;

    procedure UpdateThreadUIProgress(ThreadNo: Integer; var AllThreadCompleted: Boolean; var ErrorThrown: Boolean; var ErrorMsg: Text; var ErrorCallStack: Text; var RecProceed: Integer; var TotFileSize: Decimal; var TotCompSize: Decimal; var Archive: Record "TOO Pipou Archive") ThreadTxt: Text
    var
        ActiveSession: Record "Active Session";
        SessionEvent: Record "Session Event";
        Thread: Record "TOO Pipou Thread";
        Mgt: Codeunit "TOO Pipou Mgt.";
    begin
        if not Thread.Get(ThreadNo) then
            exit; // process may be fully completed
        AllThreadCompleted := AllThreadCompleted and (Thread.Status = Thread.Status::"Completed ✅");
        RecProceed += Thread."Total Rec. Proceed";
        TotFileSize += Thread."Files Size (KB)";
        TotCompSize += Thread."Files Compressed Size (KB)";
        if (Thread.Status <> Thread.Status::"Completed ✅") then begin
            // Check for handled Error :
            if Thread.Status = Thread.Status::"❌ Error" then begin
                ErrorThrown := true;
                ErrorMsg := Thread."Error Message";
                ErrorCallStack := Thread."Error CallStack";
            end;
            // Check for time-out and unhandled error
            ActiveSession.SetRange("Session ID", Thread."Session ID");
            if ActiveSession.IsEmpty then begin
                // Look for the closing event error
                SessionEvent.SetRange("Session ID", Thread."Session ID");
                SessionEvent.SetFilter("Event Datetime", '>%1', Thread.SystemCreatedAt);
                SessionEvent.SetFilter("Event Type", '%1|%2|%3', SessionEvent."Event Type"::Logoff, SessionEvent."Event Type"::Stop, SessionEvent."Event Type"::Close);
                if SessionEvent.FindLast() then
                    if SessionEvent.Comment <> '' then begin
                        // Close other threads
                        Thread.SetFilter("Thread No.", '<>%1', ThreadNo);
                        Thread.SetFilter(Status, '<>%1', Thread.Status::"Completed ✅");
                        if Thread.FindSet() then
                            repeat
                                StopSession(Thread."Session ID");
                            until Thread.Next() = 0;
                        // Remove exporting archive residual file partially created
                        if Archive."Process Status" = Archive."Process Status"::"⌛ Exporting" then begin
                            Sleep(500);
                            if Archive.Delete(true) then;
                        end;
                        ErrorThrown := true;
                        ErrorMsg := StrSubstNo('Unhandled error in thread %1, thread closed unexpectedly at %2.\Session ID %3 \ Closing comment : %4', ThreadNo, SessionEvent."Event Datetime", Thread."Session ID", SessionEvent.Comment);
                    end;
            end;

            // Update UI
            ThreadTxt := 'Thread ' + Format(ThreadNo) + ' : ' + Format(Thread.Status);
            if Thread.Status <> Thread.Status::"Completed ✅" then begin
                if Thread."Total Rec. To Process" > 0 then
                    ThreadTxt += '  [' + Mgt.ProgressBar(Thread."Total Rec. Proceed" / Thread."Total Rec. To Process") + ']  ';
                if Thread.Status in [Thread.Status::"Exporting Data", Thread.Status::"Compressing - Storing"] then begin
                    ThreadTxt += 'Current Table : ';
                    ThreadTxt += Format(Thread."Current Table") + ' (' + Format(Thread."Current Table Progress %") + '%)';
                end;
                if Thread.Status in [Thread.Status::"Decompressing - Decoding", Thread.Status::"Importing Data", Thread.Status::"Truncating Table", Thread.Status::Commiting] then begin
                    ThreadTxt += 'Current File : ';
                    ThreadTxt += Format(Thread."Current File") + ' (' + Format(Thread."Current File Progress %") + '%)';
                end;
            end;
        end;
    end;
    #endregion


    #region Check Running
    procedure CheckThreadsRunning()
    var
        ActiveSession: Record "Active Session";
        Archive: Record "TOO Pipou Archive";
        Thread: Record "TOO Pipou Thread";
        CanNotRunTwoExport: Label 'An another import or export has been detected and is running by user "%1", started at %2.\ Please wait for this process to finish or force kill the session to start over.';
    begin
        // Check if another export is running
        Thread.SetFilter(Status, '<>%1&<>%2', Thread.Status::"Completed ✅", Thread.Status::"❌ Error");
        if Thread.FindSet() then
            repeat
                ActiveSession.SetRange("Session ID", Thread."Session ID");
                if not ActiveSession.FindFirst() then begin
                    // Session is not running - remove "exporting" archive
                    Thread.Delete();
                    if Archive.Get(Thread."Archive Name", Thread."Archive ID") then
                        if Archive."Process Status" = Archive."Process Status"::"⌛ Exporting" then
                            Archive.Delete(true);
                end else
                    // Session running - check Archive exists
                    if Archive.Get(Thread."Archive Name", Thread."Archive ID") then
                        Error(CanNotRunTwoExport, ActiveSession."User ID", Thread.SystemCreatedAt)
                    else
                        Thread.Delete();
            until Thread.Next() = 0;
    end;
    #endregion
}