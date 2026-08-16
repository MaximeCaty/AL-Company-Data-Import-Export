page 51007 "TOO Pipou Archives"
{
    ApplicationArea = All;
    Caption = 'Company Data Archives List';
    CardPageId = "TOO Pipou Archive Card";
    InsertAllowed = false;
    ModifyAllowed = false;
    PageType = List;
    SourceTable = "TOO Pipou Archive";
    UsageCategory = Lists;

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Archive Name"; Rec."Archive Name") { }
                field("Process Status"; Rec."Process Status")
                {

                    trigger OnDrillDown()
                    begin
                        if Rec."Process Status" <> Rec."Process Status"::" " then
                            Page.Run(Page::"TOO Pipou Archive Card", Rec);
                    end;
                }
                field("Archive Sequence No."; Rec."Archive Sequence No.") { }
                field("Files Size (KB)"; Rec."Files Size (KB)") { }
                field("Files Compressed Size (KB)"; Rec."Files Compressed Size (KB)") { }
                field("Compression Ratio (%)"; Rec."Compression Ratio (%)") { }
                field("No. Files"; Rec."No. Files")
                {

                    trigger OnDrillDown()
                    var
                        ArchFiles: Record "TOO Pipou Archive Files";
                    begin
                        if Rec."Archive Name" = '' then
                            exit;
                        ArchFiles.SetRange("Archive ID", Rec."Archive ID");
                        Page.Run(Page::"TOO Pipou Archive Files", ArchFiles)
                    end;
                }
                field("Import Destination Company"; Rec."Import Destination Company") { }
                field("Imported Files"; Rec."Imported Files") { }
                field("Import Warning / Error"; Rec."Import Warning / Error") { }
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
                        ArchTables.ModifyAll("PreImport Truncated", false);
                    end;
                end;
            }
            action(ImportPath)
            {
                Caption = 'Upload Archive';
                Image = Import;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;
                ToolTip = 'Upload and store an archive file using among import method of your choice.';


                trigger OnAction()
                begin
                    Rec.UploadArchiveFileDialog();
                end;
            }

        }
    }
}