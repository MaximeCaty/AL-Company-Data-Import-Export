page 51021 "TOO Pipou Archive Card"
{
    ApplicationArea = All;
    Caption = 'Company Data Archive Card';
    InsertAllowed = false;
    ModifyAllowed = false;
    PageType = Card;
    SourceTable = "TOO Pipou Archive";

    layout
    {
        area(Content)
        {
            group(Info)
            {
                Caption = 'General';
                field("Archive Name";
                Rec."Archive Name")
                { }
                field("Archive ID"; Rec."Archive ID") { }

                group(DataContent)
                {
                    Caption = 'Data Content';

                    field("Total Records"; Rec."Total Records") { }
                    field("Files Size (KB)"; Rec."Files Size (KB)") { }
                    field("Files Compressed Size (KB)"; Rec."Files Compressed Size (KB)") { }
                    field("Compression Ratio (%)"; Rec."Compression Ratio (%)") { }
                    field("No. Files"; Rec."No. Files") { }
                    field("No. Tables"; Rec."No. Tables") { }
                }
                group(Encoding)
                {
                    field("Prefered Compression Mode"; Rec."Prefered Compression Mode") { }
                    group(CompLvl)
                    {
                        ShowCaption = false;
                        Visible = (Rec."Prefered Compression Mode" = Rec."Prefered Compression Mode"::"Auto (On-Premise)");
                        field("Compression Level"; Rec."Compression Level") { }
                    }
                    field("Enable Columns Transcoding"; Rec."Enable Columns Transcoding") { }
                }
                group(Export)
                {
                    Caption = 'Exported From';

                    field("Exported From Company"; Rec."Exported From Company") { }
                    field("Exported Date Time"; Rec."Exported Date Time") { }
                    field("Export Duration"; Rec."Export Duration") { }
                    field("Import Duration"; Rec."Import Duration") { }
                }
            }
            group(Threads)
            {
                Visible = IsProcessing;

                field("Process Status"; Rec."Process Status")
                {
                    Editable = false;
                }
                group(Import)
                {
                    Caption = 'Import';
                    Visible = (Rec."Process Status" = Rec."Process Status"::"✅ Imported") or (Rec."Process Status" = Rec."Process Status"::"✅ Partially Imported") or (Rec."Process Status" = Rec."Process Status"::"⌛ Importing");

                    field("Import Destination Company"; Rec."Import Destination Company") { }
                    field("Imported Files"; Rec."Imported Files") { }
                    field("Import Use SQL Bulk"; Rec."Import Use SQL Bulk") { }
                    field("Import Warning / Error"; Rec."Import Warning / Error") { }
                }

                grid(ProcessActions)
                {
                    ShowCaption = false;
                    field(Stop; StopTxt)
                    {
                        Editable = false;
                        ShowCaption = false;

                        trigger OnDrillDown()
                        var
                            ActiveSession: Record "Active Session";
                            Thread: Record "TOO Pipou Thread";
                            ConfirmLbl: Label 'This action will stop all threads and any uncommited import/export data will be lost. This is irreversible. Continue ?';
                        begin
                            if not Confirm(ConfirmLbl) then
                                exit;

                            // Check if another export is running
                            Thread.SetRange("Archive ID", Rec."Archive ID");
                            if Thread.FindSet() then
                                repeat
                                    // Close session
                                    if Thread."Session ID" <> 0 then begin
                                        ActiveSession.SetRange("Session ID", Thread."Session ID");
                                        if not ActiveSession.IsEmpty then
                                            StopSession(Thread."Session ID", 'Manually stopped by user ' + UserId());
                                    end;
                                until Thread.Next() = 0;
                            Thread.DeleteAll();

                            // Remove exported residual files / clear importing state
                            if Rec."Process Status" = Rec."Process Status"::"⌛ Exporting" then
                                Rec.Delete(true);
                            if Rec."Process Status" = Rec."Process Status"::"⌛ Importing" then begin
                                Rec."Process Status" := Rec."Process Status"::" ";
                                Rec.Modify();
                            end;
                        end;

                    }
                    field(Refresh; RefreshTxt)
                    {
                        Editable = false;
                        ShowCaption = false;

                        trigger OnDrillDown()
                        begin
                            CurrPage.ThreadsList.Page.Update(false);
                            UpdateProcessProgression();
                        end;
                    }
                    field(AutoRefresh; AutoRefresh)
                    {
                        Caption = 'Auto-refresh';
                    }
                }



                field(GlobalProgressBar; GlobalProgressBar)
                {
                    Caption = 'Progression total';
                    ColumnSpan = 2;
                    Editable = false;
                    Width = 25;
                }

                field(GlobalEstRemDuration; GlobalEstRemDuration)
                {
                    Caption = 'Estimated Remaining Duration';
                    Editable = false;
                    Width = 15;
                }
                field(AvgRecPerSecond; AvgRecPerSecond)
                {
                    Caption = 'Avg. Rec/S';
                    Editable = false;
                }
            }
            group(ThreadsPart)
            {
                ShowCaption = false;
                Visible = IsProcessing;

                part(ThreadsList; "TOO Pipou Threads")
                {
                    SubPageLink = "Archive ID" = field("Archive ID");
                    UpdatePropagation = Both;
                }
            }
            usercontrol(PageAutoRefreshAddin; TOOPageAutoRefreshAddin)
            {
                Visible = AutoRefresh;

                trigger AddinReady()
                begin
                    CurrPage.PageAutoRefreshAddin.Run(1000);
                end;

                trigger Refresh()
                var
                    PreviousStatusExporting: Boolean;
                    ConfirmLbl: Label 'Export as finished. Would you like to download the archive ? (~%1 %2) ?';
                begin
                    PreviousStatusExporting := (Rec."Process Status" = Rec."Process Status"::"⌛ Exporting");
                    if RefreshCounter > 900 then
                        exit; // stop after 15mn
                    if AutoRefresh and IsProcessing then begin
                        RefreshCounter += 1;
                        CurrPage.ThreadsList.Page.Update(false);
                        Rec.Get(Rec."Archive Name", Rec."Archive ID");
                        UpdateProcessProgression();
                    end;
                    if Rec."Process Status" in [Rec."Process Status"::"✅ Exported", Rec."Process Status"::"✅ Imported", Rec."Process Status"::"✅ Partially Imported", Rec."Process Status"::" "] then begin
                        AutoRefresh := false;
                        if PreviousStatusExporting and (Rec."Process Status" = Rec."Process Status"::"✅ Exported") then
                            if Confirm(StrSubstNo(ConfirmLbl, Round(Rec."Files Compressed Size (KB)" / 1024, 0.1), 'MB')) then
                                Rec.DownloadArchiveFile();
                    end else
                        CurrPage.PageAutoRefreshAddin.Run(1000);
                    CurrPage.Update(false);
                end;
            }
        }
    }

    #region Actions
    actions
    {
        area(Processing)
        {
            action(Download)
            {
                Caption = 'Download archive';
                Image = Download;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;

                trigger OnAction()
                var
                    ConfirmLbl: Label 'This archive file is ~%1 %2.\ Download the file ?';
                begin
                    if Confirm(StrSubstNo(ConfirmLbl, Round(Rec."Files Compressed Size (KB)" / 1024, 0.1), 'MB')) then
                        Rec.DownloadArchiveFile();
                end;
            }
            action(Apply)
            {
                Caption = 'Apply Data';
                Image = ImportDatabase;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;
                ToolTip = 'Apply archive data content to a specific company';

                trigger OnAction()
                var
                    PipouImport: Page "TOO Pipou Import Asst. Setup";
                begin
                    if Rec."Archive Name" <> '' then begin
                        PipouImport.SetOpenAtStep(3);
                        PipouImport.SetRecord(Rec);
                        PipouImport.SetTableView(Rec);
                        PipouImport.Run();
                    end;
                end;
            }
            action(Reset)
            {
                Caption = 'Reset Import State';
                Image = ResetStatus;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;

                trigger OnAction()
                var
                    ArchFiles: Record "TOO Pipou Archive Files";
                    ArchTables: Record "TOO Pipou Archive Tables";
                    ArchLogs: Record "TOO Pipou Import Log";
                    StatusErrLbl: Label 'The processing state must be empty to reset import.';
                begin
                    if not (Rec."Process Status" in [Rec."Process Status"::" ", Rec."Process Status"::"✅ Imported"]) then
                        Error(StatusErrLbl);

                    if Confirm(StrSubstNo('Continue and reset any current import progression for selected archive "%1" ?', Rec."Archive Name")) then begin
                        Rec."Process Status" := Rec."Process Status"::" ";
                        Rec.Modify();
                        ArchFiles.SetRange("Archive ID", Rec."Archive ID");
                        ArchFiles.ModifyAll(Imported, false);
                        ArchLogs.SetRange("Archive ID", Rec."Archive ID");
                        ArchLogs.DeleteAll();
                        ArchTables.SetRange("Archive ID", Rec."Archive ID");
                        ArchTables.ModifyAll("PreImport Truncated", false);
                    end;
                end;
            }
        }
    }
    #endregion

    trigger OnAfterGetRecord()
    var
        Thread: Record "TOO Pipou Thread";
    begin
        if Rec."Process Status" in [Rec."Process Status"::"⌛ Exporting", Rec."Process Status"::"⌛ Importing", Rec."Process Status"::"✅ Exported", Rec."Process Status"::"✅ Imported", Rec."Process Status"::"✅ Partially Imported"] then
            IsProcessing := true
        else begin
            Thread.SetRange("Archive ID", Rec."Archive ID");
            IsProcessing := not Thread.IsEmpty;
        end;
    end;

    local procedure UpdateProcessProgression()
    var
        Thread: Record "TOO Pipou Thread";
        RemProgress: Decimal;
        ElapsedTime: Duration;
    begin
        if IsProcessing then begin
            Thread.CalcSums("Total Rec. Proceed");

            // Progress bar
            if Rec."Total Records" > 0 then
                GlobalProgress := (Thread."Total Rec. Proceed" / Rec."Total Records")
            else
                GlobalProgress := 0;
            GlobalProgressBar := ProgressBar(GlobalProgress, 15);

            // Remaining Duration
            if (GlobalProgress > 0) and (Thread."Total Rec. Proceed" > 1000) then begin
                ElapsedTime := Round(CurrentDateTime - Rec."Process Started At", 1000);
                RemProgress := (1 - GlobalProgress) / GlobalProgress;
                GlobalEstRemDuration := Round(ElapsedTime * RemProgress + 5000, 10000, '>');
                AvgRecPerSecond := Round(Thread."Total Rec. Proceed" / ElapsedTime * 1000, 1);
            end else begin
                GlobalEstRemDuration := 0;
                AvgRecPerSecond := 0;
            end;
        end;
    end;

    trigger OnOpenPage()
    begin
        RefreshTxt := RefreshLbl;
        StopTxt := StopLbl;
        if Rec."Process Status" in [Rec."Process Status"::"⌛ Importing", Rec."Process Status"::"⌛ Exporting"] then
            AutoRefresh := true
        else
            AutoRefresh := false;
    end;

    procedure ProgressBar(ProgressPercent: Decimal; Len: Integer) AsciiResult: Text
    var
        i: Integer;
        ProgressChar: Integer;
    begin
        ProgressChar := Round(ProgressPercent * Len, 1, '<') + 1;
        for i := 1 to Len do
            if i < ProgressChar then
                AsciiResult += '▰'
            else
                if i = ProgressChar then
                    AsciiResult += '▴'
                else
                    AsciiResult += '▱';
    end;


    var
        AutoRefresh: Boolean;
        IsProcessing: Boolean;
        GlobalProgress: Decimal;
        GlobalEstRemDuration: Duration;
        AvgRecPerSecond: Integer;
        RefreshCounter: Integer;
        RefreshLbl: Label '🔄 Refresh';
        StopLbl: Label '🛑 Stop Process';
        GlobalProgressBar: Text;
        RefreshTxt: Text;
        StopTxt: Text;
}