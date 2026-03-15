codeunit 51014 "TOO Pipou Import Multithreads"
{
    TableNo = "Job Queue Entry";

    trigger OnRun()
    var
        Archive: Record "TOO Pipou Archive";
    begin
        Archive.Get(Rec."Record ID to Process");
        MultiThreadImport(Archive, GuiAllowed and Runforeground);
    end;

    procedure SetRunForeground(SetForeGround: Boolean)
    begin
        // Set if the process run with modal dialog progression
        Runforeground := SetForeGround;
    end;


    var
        ThreadHelper: Codeunit "TOO Pipou Threads Mgt.";
        ImportData: Codeunit "TOO Pipou Import Data";
        PipouMgt: Codeunit "TOO Pipou Mgt.";
        Runforeground: Boolean;

    #region MultiThrd Imp
    procedure MultiThreadImport(var Archive: Record "TOO Pipou Archive"; Foreground: Boolean)
    var
        Win: Dialog;
        Progress: Label 'Importing Data to company #1####\-\Elapsed time : #2########\ Estimated duration : #3#######\-\Global progression :\#4#########\SQL Data (KB) : #5########\Records : #6######\-\#7######\-\#8######\-\#9######\-\#10######\-\#11######\-\#12######';
        DataProceed: Integer;
        RecProceed: Integer;
        TotFileSize: Decimal;
        ElapsedTime: Duration;
        ThreadTxt: Text;
        ArchTotalSizeToImport: Integer;
        Thread: Record "TOO Pipou Thread";
        SessionID: Integer;
        AllThreadCompleted: Boolean;
        RemDuration: Duration;
        RemProgress: Decimal;
        GlobalProgress: Decimal;
        OtherArchive: Record "TOO Pipou Archive";
        ChangeLogSetup: Record "Change Log Setup";
        ErrorThrown: Boolean;
        ErrorMessage: Text;
        StartDT: DateTime;
    begin
        ThreadHelper.CheckThreadsRunning();

        // Verify Archive
        Archive.TestField("Archive ID");
        Archive.TestField("Number of Threads");
        Archive.CalcFields("No. Tables");
        Archive.TestField("No. Tables");
        Archive.CalcFields("Total Original Data Size (KB)");
        Archive.TestField("Total Original Data Size (KB)");
        Archive.TestField("Process Status", Archive."Process Status"::" ");
        Archive.TestField("Import Destination Company");
        if (Archive."Number of Threads" < 1) or (Archive."Number of Threads" > 6) then
            Error('The number of threads to run the process must be within 1-6 range.');
        ArchTotalSizeToImport := CalcArchiveImportTotalSize(Archive);

        // Verify that change log is OFF
        if not Archive."Import Use SQL Bulk" then begin
            ChangeLogSetup.ChangeCompany(Archive."Import Destination Company");
            if ChangeLogSetup.Get() then
                ChangeLogSetup.TestField("Change Log Activated", false);
        end;

        // Reset other archive process state
        OtherArchive.SetFilter("Archive ID", '<>%1', Archive."Archive ID");
        OtherArchive.ModifyAll("Process Status", OtherArchive."Process Status"::" ");

        // Split tables ranges across threads
        ThreadHelper.CreateImportThreads(Archive);

        // Set state to importing
        Archive."Process Status" := Archive."Process Status"::"⌛ Importing";
        Archive."Process Started At" := CurrentDateTime;
        Archive."Size To Process (KB)" := ArchTotalSizeToImport;
        Archive.Modify();
        Commit();

        if Archive."Number of Threads" = 1 then begin
            // Debug purpose - foreground run
            Win.Open('Importing...');
            Thread.Get(1);
            ImportData.Run(Thread);
            RecProceed := Thread."Total Rec. Proceed";
            TotFileSize := Thread."Files Size (KB)";
            Win.Close();
        end else begin
            Win.Open('Starting Threads...');
            // Start sessions
            Thread.Get(1);
            StartSession(SessionID, Codeunit::"TOO Pipou Import Data", CompanyName, Thread);
            if Archive."Number of Threads" > 1 then begin
                Thread.Get(2);
                StartSession(SessionID, Codeunit::"TOO Pipou Import Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 2 then begin
                Thread.Get(3);
                StartSession(SessionID, Codeunit::"TOO Pipou Import Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 3 then begin
                Thread.Get(4);
                StartSession(SessionID, Codeunit::"TOO Pipou Import Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 4 then begin
                Thread.Get(5);
                StartSession(SessionID, Codeunit::"TOO Pipou Import Data", CompanyName, Thread);
            end;
            if Archive."Number of Threads" > 5 then begin
                Thread.Get(6);
                StartSession(SessionID, Codeunit::"TOO Pipou Import Data", CompanyName, Thread);
            end;
            Win.Close();

            if not Foreground then exit;

            StartDT := CurrentDateTime;

            // Monitor thread until all data proceed
            Win.Open(Progress);
            Win.Update(1, Archive."Exported From Company");
            DataProceed := 0;
            while (not AllThreadCompleted) do begin
                sleep(900);

                AllThreadCompleted := true; // false if any thread not completed
                DataProceed := 0;
                RecProceed := 0;
                TotFileSize := 0;

                // Thread 1 :
                ThreadTxt := ThreadHelper.UpdateThreadProgress(1, AllThreadCompleted, ErrorThrown, ErrorMessage, DataProceed, RecProceed, TotFileSize, Archive);
                Win.Update(7, ThreadTxt);
                if ErrorThrown then ThrowError(Archive, ErrorMessage);
                // Thread 2 :
                if Archive."Number of Threads" > 1 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(2, AllThreadCompleted, ErrorThrown, ErrorMessage, DataProceed, RecProceed, TotFileSize, Archive);
                    Win.Update(8, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 3 :
                if Archive."Number of Threads" > 2 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(3, AllThreadCompleted, ErrorThrown, ErrorMessage, DataProceed, RecProceed, TotFileSize, Archive);
                    Win.Update(9, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 4 :
                if Archive."Number of Threads" > 3 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(4, AllThreadCompleted, ErrorThrown, ErrorMessage, DataProceed, RecProceed, TotFileSize, Archive);
                    Win.Update(10, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 5 :
                if Archive."Number of Threads" > 4 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(5, AllThreadCompleted, ErrorThrown, ErrorMessage, DataProceed, RecProceed, TotFileSize, Archive);
                    Win.Update(11, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;
                // Thread 6 :
                if Archive."Number of Threads" > 5 then begin
                    ThreadTxt := ThreadHelper.UpdateThreadProgress(6, AllThreadCompleted, ErrorThrown, ErrorMessage, DataProceed, RecProceed, TotFileSize, Archive);
                    Win.Update(12, ThreadTxt);
                    if ErrorThrown then ThrowError(Archive, ErrorMessage);
                end;

                // Global progression
                GlobalProgress := ((DataProceed / ArchTotalSizeToImport) + (RecProceed / Archive."Total Records")) / 2;
                Win.Update(4, PipouMgt.ProgressBar(GlobalProgress));
                Win.Update(5, Format(DataProceed) + ' / ' + Format(ArchTotalSizeToImport));
                Win.Update(6, Format(RecProceed) + ' / ' + Format(Archive."Total Records"));

                // Elapsed time
                ElapsedTime := Round(CurrentDateTime - StartDT, 1000);
                Win.Update(2, ElapsedTime);
                // Estimate remaining (after 0.5% progress)
                if (GlobalProgress >= 0.005) and (ArchTotalSizeToImport > 0) then begin
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
        Archive.Get(Archive."Archive Name", Archive."Archive ID");
        Archive."Process Status" := Archive."Process Status"::" ";
        Archive.Modify();
        Commit();
        Error(Msg);
    end;

    local procedure CalcArchiveImportTotalSize(var Archive: Record "TOO Pipou Archive") TotalImportSize: Integer
    var
        ArchiveFiles: Record "TOO Pipou Archive Files";
        ArchiveTable: Record "TOO Pipou Archive Tables";
        RecAvgSize: Decimal;
    begin
        ArchiveTable.SetRange("Archive ID", Archive."Archive ID");
        ArchiveTable.SetRange("Select For Import", true);
        ArchiveTable.SetFilter("Matched Table ID", '<>0');
        ArchiveTable.SetFilter("Match Status", '<>%1', ArchiveTable."Match Status"::Missing);
        // Exclude itself
        ArchiveTable.SetFilter("Table ID", '<>%1&<>%2&<>%3&<>%4&<>%5&<>%6', Database::"TOO Pipou Archive", Database::"TOO Pipou Archive Fields", Database::"TOO Pipou Archive Tables", Database::"TOO Pipou Archive Files", database::"TOO Pipou Thread", Database::"TOO Temp Blob");
        if ArchiveTable.FindSet() then
            repeat
                // Calc record size
                RecAvgSize := ArchiveTable."Original Data Size (KB)" / ArchiveTable."No. of Records";
                ArchiveFiles.SetRange("Archive ID", Archive."Archive ID");
                ArchiveFiles.SetRange(Imported, false);
                ArchiveFiles.SetRange("Table ID", ArchiveTable."Table ID");
                ArchiveFiles.CalcSums("Number Of Recs");
                TotalImportSize += Round(RecAvgSize * ArchiveFiles."Number Of Recs", 1);
            until ArchiveTable.Next() = 0;
    end;
    #endregion
}