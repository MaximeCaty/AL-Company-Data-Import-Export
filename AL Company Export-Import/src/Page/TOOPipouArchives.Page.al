page 51007 "TOO Pipou Archives"
{
    Caption = 'Company Data Archives';
    PageType = List;
    UsageCategory = Lists;
    ApplicationArea = All;
    SourceTable = "TOO Pipou Archive";
    ModifyAllowed = false;
    InsertAllowed = false;
    CardPageId = "TOO Pipou Archive Card";

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Archive Name"; Rec."Archive Name")
                {
                    ApplicationArea = All;
                }
                field("Process Status"; Rec."Process Status")
                {
                    ApplicationArea = All;

                    trigger OnDrillDown()
                    begin
                        if Rec."Process Status" <> Rec."Process Status"::" " then
                            page.Run(Page::"TOO Pipou Archive Card", Rec);
                    end;
                }
                field("Archive Sequence No."; Rec."Archive Sequence No.")
                {
                    ApplicationArea = All;
                }
                field("Files Size (KB)"; Rec."Files Size (KB)")
                {
                    ApplicationArea = All;
                }
                field("Files Compressed Size (KB)"; Rec."Files Compressed Size (KB)")
                {
                    ApplicationArea = All;
                }
                field("Compression Ratio (%)"; Rec."Compression Ratio (%)")
                {
                    ApplicationArea = All;
                }
                field("No. Files"; Rec."No. Files")
                {
                    ApplicationArea = All;

                    trigger OnDrillDown()
                    var
                        ArchFiles: Record "TOO Pipou Archive Files";
                    begin
                        if Rec."Archive Name" = '' then exit;
                        ArchFiles.SetRange("Archive ID", Rec."Archive ID");
                        page.run(Page::"TOO Pipou Archive Files", ArchFiles)
                    end;
                }
                field("Import Destination Company"; Rec."Import Destination Company")
                {
                    ApplicationArea = All;
                }
                field("Imported Files"; Rec."Imported Files")
                {
                    ApplicationArea = All;
                }
                field("Import Warning / Error"; Rec."Import Warning / Error")
                {
                    ApplicationArea = All;
                }
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
                var
                    ConfirmLbl: Label 'This archive file is ~%1 %2.\ Download the file ?';
                begin
                    if Confirm(StrSubstNo(ConfirmLbl, round(Rec."Files Compressed Size (KB)" / 1024, 0.1), 'MB')) then
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
                        PipouImport.SetOpenAtStep(3);
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
                    if not (Rec."Process Status" in [Rec."Process Status"::" ", Rec."Process Status"::"✅ Imported", Rec."Process Status"::"✅ Partially Imported"]) then
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
            action(ImportPath)
            {
                Caption = 'Upload Archive';
                ToolTip = 'Upload and store an archive file using among import method of your choice.';
                ApplicationArea = All;
                Image = Import;
                Promoted = true;
                PromotedOnly = true;
                PromotedCategory = Process;
                PromotedIsBig = true;


                trigger OnAction();
                begin
                    Rec.UploadArchiveFileDialog();
                end;
            }

        }
    }
}