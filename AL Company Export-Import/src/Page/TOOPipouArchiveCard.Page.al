page 51021 "TOO Pipou Archive Card"
{
    PageType = Card;
    ApplicationArea = All;
    SourceTable = "TOO Pipou Archive";
    ModifyAllowed = false;
    InsertAllowed = false;
    Caption = 'Pipou Archive';


    layout
    {
        area(Content)
        {
            group(Info)
            {
                Caption = 'General';
                field("Archive Name";
                Rec."Archive Name")
                {
                    ApplicationArea = all;
                }
                field("Archive ID"; Rec."Archive ID")
                {
                    ApplicationArea = all;
                }

                group(Content)
                {
                    Caption = 'Data Content';

                    field("Total Records"; Rec."Total Records")
                    {
                        ApplicationArea = all;
                    }
                    field("Total Size (KB)"; Rec."Total Original Data Size (KB)")
                    {
                        ApplicationArea = all;
                    }
                    field("Files Compressed Size (KB)"; Rec."Files Compressed Size (KB)")
                    {
                        ApplicationArea = all;
                    }
                    field("Compression Ratio (%)"; Rec."Compression Ratio (%)")
                    {
                        ApplicationArea = all;
                    }
                    field("No. Files"; Rec."No. Files")
                    {
                        ApplicationArea = all;
                    }
                    field("No. Tables"; Rec."No. Tables")
                    {
                        ApplicationArea = all;
                    }
                }
                group(Encoding)
                {
                    field("Prefered Compression Mode"; Rec."Prefered Compression Mode")
                    {
                        ApplicationArea = all;
                    }
                    field("Enable Columns Transcoding"; Rec."Enable Columns Transcoding")
                    {
                        ApplicationArea = all;
                    }
                    field("Enable Optimal Encode"; Rec."Enable Optimal Encode")
                    {
                        ApplicationArea = all;
                    }
                }
            }
            group(Threads)
            {
                Visible = IsProcessing;

                field("Process Status"; Rec."Process Status")
                {
                    Editable = false;
                }

                grid(ProcessActions)
                {
                    ShowCaption = false;
                    Field(Stop; StopTxt)
                    {
                        ShowCaption = false;
                        Editable = false;

                        trigger OnDrillDown()
                        var
                            Thread: Record "TOO Pipou Thread";
                            ActiveSession: Record "Active Session";
                            ConfirmLbl: Label 'This action will stop all threads and any uncommited import/export data will be lost. This is irreversible. Continue ?';
                        begin
                            if not Confirm(ConfirmLbl) then exit;

                            // Check if another export is running
                            Thread.SetRange("Archive ID", Rec."Archive ID");
                            if Thread.FindSet() then begin
                                repeat
                                    // Close session
                                    if Thread."Session ID" <> 0 then begin
                                        ActiveSession.SetRange("Session ID", Thread."Session ID");
                                        if not ActiveSession.IsEmpty then
                                            StopSession(Thread."Session ID", 'Manually stopped by user ' + UserId());
                                    end;
                                until Thread.Next() = 0;
                            end;
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
                    Field(Refresh; RefreshTxt)
                    {
                        ShowCaption = false;
                        Editable = false;

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

                grid(ProgressBarGrid)
                {
                    ShowCaption = false;
                    field(GlobalProgressBar; GlobalProgressBar)
                    {
                        Caption = 'Progression total';
                        Editable = false;
                        Width = 25;
                        ColumnSpan = 2;
                    }
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
            group(Export)
            {
                Caption = 'Export';

                field("Exported From Company"; Rec."Exported From Company")
                {
                    ApplicationArea = all;
                }
                field("Exported Date Time"; Rec."Exported Date Time")
                {
                    ApplicationArea = all;
                }
                field("Diff. Export Start DT"; Rec."Diff. Export Start DT")
                {
                    ApplicationArea = all;
                }
            }
            group(Import)
            {
                Caption = 'Import';

                field("Import Destination Company"; Rec."Import Destination Company")
                {
                    ApplicationArea = all;
                }
                field("Imported Files"; Rec."Imported Files")
                {
                    ApplicationArea = all;
                }
                field("Import Warning / Error"; Rec."Import Warning / Error")
                {
                    ApplicationArea = all;
                }
                field("Import Use SQL Bulk"; Rec."Import Use SQL Bulk")
                {
                    ApplicationArea = All;
                }
            }
            usercontrol(PageAutoRefreshAddin; TOOPageAutoRefreshAddin)
            {
                Visible = AutoRefresh;

                trigger AddinReady()
                begin
                    CurrPage.PageAutoRefreshAddin.Run(2500);
                end;

                trigger Refresh()
                begin
                    if RefreshCounter > 900 then
                        exit; // stop after 15mn
                    if AutoRefresh and IsProcessing then begin
                        RefreshCounter += 1;
                        if RefreshCounter mod 2 = 1 then
                            CurrPage.Update(false)
                        else
                            CurrPage.ThreadsList.Page.Update(false);
                        UpdateProcessProgression();
                    end;
                    CurrPage.PageAutoRefreshAddin.Run(2500);
                end;
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Download)
            {
                Caption = 'Download archive';
                ApplicationArea = All;
                Image = Download;
                Promoted = true;
                PromotedOnly = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                begin
                    Rec.DownloadArchiveFile();
                end;
            }
            action(Apply)
            {
                Caption = 'Apply Data';
                ToolTip = 'Apply archive data content to a specific company';
                ApplicationArea = All;
                Image = ImportDatabase;
                Promoted = true;
                PromotedOnly = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    PipouImport: Page "TOO Pipou Import Asst. Setup";
                begin
                    if Rec."Archive Name" <> '' then begin
                        PipouImport.SetRecord(Rec);
                        PipouImport.SetTableView(Rec);
                        PipouImport.Run();
                    end;
                end;
            }
            action("Reset")
            {
                Caption = 'Reset Import State';
                ApplicationArea = All;
                Image = ResetStatus;
                Promoted = true;
                PromotedOnly = true;
                PromotedCategory = Process;
                PromotedIsBig = true;

                trigger OnAction()
                var
                    ArchTables: Record "TOO Pipou Archive Tables";
                    ArchFiles: Record "TOO Pipou Archive Files";
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
                        ArchTables.ModifyAll("Preimport Truncated", false);
                    end;
                end;
            }
        }
    }

    trigger OnAfterGetRecord()
    var
        Threads: Record "TOO Pipou Thread";
    begin
        if Rec."Process Status" in [Rec."Process Status"::"⌛ Exporting", Rec."Process Status"::"⌛ Importing", Rec."Process Status"::"✅ Exported", Rec."Process Status"::"✅ Imported"] then
            IsProcessing := true
        else begin
            Threads.SetRange("Archive ID", Rec."Archive ID");
            IsProcessing := not Threads.IsEmpty;
        end;
    end;

    local procedure UpdateProcessProgression()
    var
        Threads: Record "TOO Pipou Thread";
        ElapsedTime: Duration;
        RemProgress: Decimal;
    begin
        if TotalSizeToProceedKB = 0 then begin
            if Rec."Process Status" = Rec."Process Status"::"⌛ Importing" then
                TotalSizeToProceedKB := Rec."Size To Process (KB)";
            if Rec."Process Status" = Rec."Process Status"::"⌛ Exporting" then
                TotalSizeToProceedKB := Rec."Total Original Data Size (KB)";
        end;

        if IsProcessing then begin
            // Progress bar
            Threads.CalcSums("Proceed Size KB");
            if TotalSizeToProceedKB > 0 then
                GlobalProgress := (Threads."Proceed Size KB" / TotalSizeToProceedKB)
            else
                GlobalProgress := 0;
            GlobalProgressBar := PipouMgT.ProgressBar(GlobalProgress);

            // Remaining Duration
            Threads.CalcSums("Total Rec. Proceed");
            if (GlobalProgress > 0) and (Threads."Total Rec. Proceed" > 1000) then begin
                ElapsedTime := Round(CurrentDateTime - Rec."Process Started At", 1000);
                RemProgress := (1 - GlobalProgress) / GlobalProgress;
                GlobalEstRemDuration := Round(ElapsedTime * RemProgress + 5000, 10000, '>');
                AvgRecPerSecond := round(Threads."Total Rec. Proceed" / ElapsedTime * 1000, 1);
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
        AutoRefresh := true;
    end;

    var
        TotalSizeToProceedKB: Integer;
        IsProcessing: Boolean;
        GlobalProgress: Decimal;
        GlobalProgressBar: Text;
        GlobalEstRemDuration: Duration;
        PipouMgT: Codeunit "TOO Pipou Mgt.";
        AvgRecPerSecond: Integer;
        RefreshTxt: Text;
        StopTxt: Text;
        RefreshLbl: Label '🔄 Refresh';
        StopLbl: Label '🛑 Stop Process';
        AutoRefresh: Boolean;
        RefreshCounter: Integer;
}