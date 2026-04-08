codeunit 51015 "TOO Pipou Threads Mgt."
{

    #region Export Thread
    procedure CreateExportThreads(var Archive: Record "TOO Pipou Archive")
    var
        ArchiveTables: Record "TOO Pipou Archive Tables";
        Threads: Record "TOO Pipou Thread";
        I: Integer;
        ThreadTotalRecSize: array[6] of Integer;
        MinSum: Integer;
        MinThread: Integer;
    begin
        // Create thread information record and split table range across threads
        Threads.DeleteAll();

        // Split threads
        // Loop through table in decreasing size order for better splitting
        ArchiveTables.ReadIsolation := ArchiveTables.ReadIsolation::ReadUncommitted;
        ArchiveTables.SetRange("Archive ID", Archive."Archive ID");

        /*if Archive."Number of Threads" = 1 then begin
            // Single thread
            Threads.Init();
            Threads."Thread No." := 1;
            Threads."Archive ID" := Archive."Archive ID";
            Threads."Archive Name" := Archive."Archive Name";
            ArchiveTables.FindLast();
            Threads."Total Rec. To Process" := Archive."Total Records";
            Threads.Insert();
        end else begin*/
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

        // Loop tables in decreasing size order
        ArchiveTables.SetCurrentKey("Archive ID", "No. of Records");
        ArchiveTables.SetAscending("No. of Records", false);
        ArchiveTables.FindSet();
        repeat
            // Find thread with smallest current sum
            MinSum := ThreadTotalRecSize[1];
            MinThread := 1;
            for i := 2 to Archive."Number of Threads" do begin
                if ThreadTotalRecSize[i] < MinSum then begin
                    MinSum := ThreadTotalRecSize[i];
                    MinThread := i;
                end;
            end;

            ThreadTotalRecSize[MinThread] += ArchiveTables."No. of Records"; // table size

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
        //end;
        Commit(); // need to store the thread for sub sessions
    end;
    #endregion

    #region Import Threads
    procedure CreateImportThreads(var Archive: Record "TOO Pipou Archive")
    var
        ArchiveTables: Record "TOO Pipou Archive Tables";
        ArchiveFiles: Record "TOO Pipou Archive Files";
        Threads: Record "TOO Pipou Thread";
        I: Integer;
        ThreadTotalRecSize: array[6] of Integer;
        MinSum: Integer;
        MinThread: Integer;
        FileTableContentPercent: Decimal;
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
        ArchiveFiles.SetFilter("Table ID", '<>%1&<>%2&<>%3&<>%4&<>%5&<>%6', Database::"TOO Pipou Archive", Database::"TOO Pipou Archive Fields", Database::"TOO Pipou Archive Tables", Database::"TOO Pipou Archive Files", database::"TOO Pipou Thread", Database::"TOO Temp Blob");

        /*if Archive."Number of Threads" = 1 then begin
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
        end else begin*/
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

        // Loop files in decreasing size order
        ArchiveFiles.SetCurrentKey("Archive ID", "Uncompressed Length");
        ArchiveFiles.SetAscending("Uncompressed Length", false);
        ArchiveFiles.FindSet();
        repeat
            // Find thread with smallest current sum
            MinSum := ThreadTotalRecSize[1];
            MinThread := 1;
            for i := 2 to Archive."Number of Threads" do begin
                if ThreadTotalRecSize[i] < MinSum then begin
                    MinSum := ThreadTotalRecSize[i];
                    MinThread := i;
                end;
            end;

            ArchiveTables.Get(ArchiveFiles."Archive ID", ArchiveFiles."Table ID");
            FileTableContentPercent := ArchiveFiles."Number Of Recs" / ArchiveTables."No. of Records";

            ThreadTotalRecSize[MinThread] += ArchiveFiles."Number Of Recs"; // table size 

            ArchiveFiles."Affected Thread" := MinThread;
            ArchiveFiles.Modify();

        until (ArchiveFiles.Next() = 0);

        // Update threads Size
        Threads.Reset();
        if Threads.FindSet(true) then
            repeat
                Threads."Total Rec. To Process" := ThreadTotalRecSize[Threads."Thread No."];
                Threads.Modify();
            until Threads.Next() = 0;
        //end;
        Commit(); // need to store the thread for sub sessions
    end;
    #endregion

    #region Thread Progression
    procedure UpdateThreadProgress(ThreadNo: Integer; var AllThreadCompleted: Boolean; var ErrorThrown: Boolean; var ErrorMsg: Text; var RecProceed: Integer; var TotFileSize: Decimal; var Archive: Record "TOO Pipou Archive") ThreadTxt: Text

    var
        TotCompSize: Decimal;
    begin
        exit(UpdateThreadProgress(ThreadNo, AllThreadCompleted, ErrorThrown, ErrorMsg, RecProceed, TotFileSize, TotCompSize, Archive));
    end;

    procedure UpdateThreadProgress(ThreadNo: Integer; var AllThreadCompleted: Boolean; var ErrorThrown: Boolean; var ErrorMsg: Text; var RecProceed: Integer; var TotFileSize: Decimal; var TotCompSize: Decimal; var Archive: Record "TOO Pipou Archive") ThreadTxt: Text
    var
        Thread: Record "TOO Pipou Thread";
        SessionEvent: Record "Session Event";
        ActiveSession: Record "Active Session";
        Mgt: Codeunit "TOO Pipou Mgt.";
    begin
        if not Thread.Get(ThreadNo) then exit; // process may be fully completed
        AllThreadCompleted := AllThreadCompleted and (Thread.Status = Thread.Status::"Completed ✅");
        RecProceed += Thread."Total Rec. Proceed";
        TotFileSize += Thread."Files Size (KB)";
        TotCompSize += Thread."Files Compressed Size (KB)";
        if (Thread.Status <> Thread.Status::"Completed ✅") then begin
            // Check for handled Error :
            if Thread.Status = Thread.Status::"❌ Error" then begin
                ErrorThrown := true;
                ErrorMsg := Thread."Error Message";
            end;
            // Check for time-out and unhandled error
            ActiveSession.SetRange("Session ID", Thread."Session ID");
            if ActiveSession.IsEmpty then begin
                // Look for the closing event error
                SessionEvent.SetRange("Session ID", Thread."Session ID");
                SessionEvent.SetFilter("Event Datetime", '>%1', Thread.SystemCreatedAt);
                SessionEvent.SetFilter("Event Type", '%1|%2|%3', SessionEvent."Event Type"::Logoff, SessionEvent."Event Type"::Stop, SessionEvent."Event Type"::Close);
                if SessionEvent.FindLast() then begin
                    if SessionEvent.Comment <> '' then begin
                        // Close other threads
                        Thread.Setfilter("Thread No.", '<>%1', ThreadNo);
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
            end;

            // Update UI
            ThreadTxt := 'Thread ' + Format(ThreadNo) + ' : ' + Format(Thread.Status);
            if Thread.Status <> Thread.Status::"Completed ✅" then begin
                if Thread."Total Rec. To Process" > 0 then
                    ThreadTxt += '  [' + Mgt.ProgressBar(Thread."Total Rec. Proceed" / Thread."Total Rec. To Process") + ']  ';
                if Thread.Status IN [thread.Status::"Exporting Data", thread.Status::"Compressing - Storing"] then begin
                    ThreadTxt += 'Current Table : ';
                    ThreadTxt += format(Thread."Current Table") + ' (' + Format(Thread."Current Table Progress %") + '%)';
                end;
                if Thread.Status IN [thread.Status::"Decompressing - Decoding", thread.Status::"Importing Data", thread.Status::"Truncating Table", thread.Status::Commiting] then begin
                    ThreadTxt += 'Current File : ';
                    ThreadTxt += format(Thread."Current File") + ' (' + Format(Thread."Current File Progress %") + '%)';
                end;
            end;
        end;
    end;
    #endregion


    #region Check Running
    procedure CheckThreadsRunning()
    var
        Thread: Record "TOO Pipou Thread";
        ActiveSession: Record "Active Session";
        Archive: Record "TOO Pipou Archive";
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