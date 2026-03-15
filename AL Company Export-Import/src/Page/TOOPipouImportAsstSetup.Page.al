page 51018 "TOO Pipou Import Asst. Setup"
{
    ApplicationArea = All;
    Caption = 'Assisted company data import', Comment = 'Import données société assisté';
    PageType = NavigatePage;
    UsageCategory = Lists;
    SourceTable = "TOO Pipou Archive";
    InsertAllowed = false;
    DeleteAllowed = false;

    layout
    {
        area(Content)
        {
            // *** Top Banner ***
            group(StandardBanner)
            {
                Caption = '', Locked = true;
                Editable = false;
                ShowCaption = false;
                Visible = not FinishEnable;

                field(MediaResourcesStandard; MediaResourcesStandard."Media Reference")
                {
                    Editable = false;
                    ShowCaption = false;
                }
            }
            #region Step 1 Intro
            group(Step1)
            {
                Caption = '', Locked = true;
                InstructionalText = '', Locked = true;
                Visible = Step1Visible;

                group(Group10)
                {
                    Caption = 'Let''s Go', Comment = 'C''est parti';
                    InstructionalText = 'Welcome to the Pipou Company data import wizard. Fill in the informations at each step until you see the “Start Import” button.', Comment = 'Bienvenue dans l''assistant d''import de données sociétés. Remplissez les informations à chaque étape jusqu''à voir le bouton "Lancer l''import".';
                }
                group(Group11)
                {
                    Caption = '', Locked = true;
                    InstructionalText = 'The export process will start once you press the button in last step.', Comment = 'Le processus d''import débutera après avoir cliquer sur le bouton en dermière étape.';
                }
                group(Group12)
                {
                    Caption = 'Click on "Next" to begin.', Comment = 'Cliquer sur "Suivant" pour commencer.';
                    InstructionalText = '', Locked = true;
                }
            }
            #endregion

            #region Step2 File
            group(Step2)
            {
                Caption = 'Archive File', Comment = 'Choix du fichier à importer';
                InstructionalText = 'Specify the archive file to import from.', Comment = 'Spécifier le fichier à importer.';
                Visible = Step2Visible;

                field(UploadNewfile; UploadNewFileLbl)
                {
                    ShowCaption = false;
                    Editable = false;

                    trigger OnDrillDown()
                    begin
                        if Rec.UploadArchiveFileDialog() then
                            ArchiveName := Rec."Archive Name";
                    end;
                }
                field(OrLbl; OrLbl)
                {
                    ShowCaption = false;
                    Editable = false;
                }

                field(SelectExistingFile; SelectExistingFileLbl)
                {
                    ShowCaption = false;
                    Editable = false;
                }

                field(ArchiveName; ArchiveName)
                {
                    Caption = 'Archive File';
                    ApplicationArea = All;
                    ShowMandatory = true;
                    NotBlank = true;
                    TableRelation = "TOO Pipou Archive"."Archive Name" where("Process Status" = Filter(" " | "⌛ Partially Imported"));

                    trigger OnValidate()
                    var
                        PipouChunks: Record "TOO Pipou Archive Files";
                        ConfResetImport: Label 'The archive data %1 as already been fully imported in company %2. Would you like to reset this archive import and start over ?';
                        Logs: Record "TOO Pipou Import Log";
                    begin
                        Rec.SetRange("Archive Name", ArchiveName);
                        Rec.FindFirst();
                        ArchiveName := Rec."Archive Name";

                        // Ask to reset import ?
                        if Rec."Process Status" = Rec."Process Status"::"✅ Imported" then
                            if confirm(StrSubstNo(ConfResetImport, ArchiveName, Rec."Import Destination Company")) then begin
                                Rec."Process Status" := Rec."Process Status"::" ";
                                Rec."Import Destination Company" := Rec."Import Destination Company";
                                Rec.Modify();
                                PipouChunks.SetRange("Archive Name", ArchiveName);
                                PipouChunks.SetRange("Archive ID", Rec."Archive ID");
                                PipouChunks.ModifyAll(Imported, false);
                                Logs.SetRange("Archive Name", ArchiveName);
                                Logs.SetRange("Archive ID", Rec."Archive ID");
                                Logs.DeleteAll();
                            end;
                        if Rec."Number of Threads" = 0 then begin
                            Rec."Number of Threads" := 4;
                            rec.Modify();
                        end;
                    end;

                }


            }
            #endregion
            #region Step3 Dest. & Info
            group(Step3)
            {
                Caption = 'Destination', Comment = 'Déstination';
                InstructionalText = 'Specify the company where you like to import the datas. Select tables to import in next step.', Comment = 'Spécifier la société ou importer les données. Le choix des tables a importer a la prochaine étape.';
                Visible = Step3Visible;

                field(ImportCompanyName; Rec."Import Destination Company")
                {
                    Caption = 'Import To Company Name';
                    ApplicationArea = all;
                    TableRelation = Company;
                    ShowMandatory = true;
                    NotBlank = true;

                    trigger OnValidate()
                    var
                        ChangeLogSetup: Record "Change Log Setup";
                    begin
                        // Verify that change log is OFF in target company
                        if ImportMethod = ImportMethod::"AL Record.Insert" then begin
                            ChangeLogSetup.ChangeCompany(Rec."Import Destination Company");
                            if ChangeLogSetup.Get() then
                                ChangeLogSetup.TestField("Change Log Activated", false);
                        end;
                    end;
                }

                field(DeleteData; Rec.DeleteData)
                {
                    ToolTip = 'Clean any existing table data before importing. The import will fail if any inserted record already exists, leave it to true unless you are importing a differential data file.';
                }

                group(ImportDataAcessGroup)
                {
                    Caption = '', Locked = true;
                    InstructionalText = 'Select the method to import data.', Comment = 'Choix de methode d''import.';

                    field(ImportMethod; ImportMethod)
                    {
                        Caption = 'Database Access', Comment = 'Acces a la base de donnees.';
                        ApplicationArea = All;
                        ToolTip = 'Specify the method used to import the datas. For OnPremise instance, SQLBulkCopy is 4-5x faster and bypass any Business Central events and trigger, and can also import audit fields.';

                        trigger OnValidate()
                        var
                            ChangeLogSetup: Record "Change Log Setup";
                        begin
                            Rec."Import Use SQL Bulk" := (ImportMethod = ImportMethod::"DotNet SqlBulkCopy");
                            Rec.Modify();

                            // Verify that change log is OFF in target company
                            if ImportMethod = ImportMethod::"AL Record.Insert" then begin
                                ChangeLogSetup.ChangeCompany(Rec."Import Destination Company");
                                if ChangeLogSetup.Get() then
                                    ChangeLogSetup.TestField("Change Log Activated", false);
                            end;
                        end;
                    }
                }

                group(Info)
                {
                    Caption = 'Archive information';

                    group(ExportFrom)
                    {
                        Caption = 'Exported From';

                        field("Exported From Company"; Rec."Exported From Company")
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                        field("Exported Date Time"; Rec."Exported Date Time")
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                        field("Diff. Export Start DT"; Rec."Diff. Export Start DT")
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                    }
                    group(DataCont)
                    {
                        Caption = 'Data content';
                        field("Prefered Compression Mode"; Rec."Prefered Compression Mode")
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                        field("Total Tables"; Format(Rec."Total Tables", 0, '<Sign><Integer Thousand><1000Character, >'))
                        {
                            ApplicationArea = all;
                            Editable = false;

                        }
                        field("Total Records"; Format(Rec."Total Records", 0, '<Sign><Integer Thousand><1000Character, >'))
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                        field("Total Size (KB)"; Format(Rec."Total Original Data Size (KB)", 0, '<Sign><Integer Thousand><1000Character, >'))
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                        field("Files Compressed Size (KB)"; Format(Rec."Files Compressed Size (KB)", 0, '<Sign><Integer Thousand><1000Character, >'))
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                        field("Compression Ratio (%)"; Rec."Compression Ratio (%)")
                        {
                            ApplicationArea = all;
                            Editable = false;
                        }
                    }
                }
            }
            #endregion

            #region Step 4 Data Scope
            group(Step4)
            {
                Caption = 'Data Scope', Comment = 'Périmètre des données';
                InstructionalText = 'Review and modify the selection of table data to import.', Comment = 'Passer en revue la liste des tables a importer et modifier la selection si besoin.';
                Visible = Step4Visible;

                part(TableList; "TOO Pipou Import Tables Sub")
                {
                    SubPageLink = "Archive ID" = field("Archive ID"), "Import Completed" = const(false);
                }
            }
            #endregion

            #region Step 5 Import
            group(Step5)
            {
                Caption = 'Run import !', Comment = 'Lancer l''import !';
                InstructionalText = 'All parameters were set. You can review the information bellow. Click "Start Import" to launch the process of importing all data from the selected archive. Encountered errors and warnings will show once the process is finished.',
                        Comment = 'Tous les paramètres ont été saisis. Cliquez sur "Lancer l''import" pour demarrer le processus d''import. Les avertissements et erreurs rencontré pendant le traitement seront afficher à la fin du processus.';
                Visible = Step5Visible;

                group(Group51)
                {
                    Caption = 'Summary', Comment = 'Recapitulatif';

                    field("Import Company Name 2"; Rec."Import Destination Company")
                    {
                        Caption = 'Destination Company Name', Comment = 'Nom de la société destination';
                        Editable = false;
                    }
                    field(CompanyTotalTables; CompanyTotalTables)
                    {
                        Caption = 'Tables Selected', Comment = 'Nb. Tables sélectionnées';
                        Editable = false;
                    }
                    field(CompanyTotalDataSize2; Format(CompanyTotalDataSize, 0, '<Sign><Integer Thousand><1000Character, >') + ' KB')
                    {
                        Caption = 'Total Selected Size', Comment = 'Poids données à importer';
                        Editable = false;
                    }
                }
                group(Group52)
                {
                    Caption = 'Multithreading', Comment = 'Exécution parallèle';

                    field(MultiThreading; Rec."Number of Threads")
                    {
                        Caption = 'Number of Threads', Comment = 'Nombre de thread';
                        NotBlank = true;
                        MinValue = 1;
                        MaxValue = 6;
                    }
                }
            }
            #endregion

            // *** Finish banner ***
            group(FinishedBanner)
            {
                Caption = '', Locked = true;
                Editable = false;
                ShowCaption = false;
                Visible = Step5Visible;

                field(MediaResourcesDone; MediaResourcesDone."Media Reference")
                {
                    Editable = false;
                    ShowCaption = false;
                }
            }
        }
    }

    #region Actions
    actions
    {
        area(Processing)
        {
            action(Back)
            {
                Caption = 'Previous', Comment = 'Précédent';
                Enabled = BackEnable;
                Image = PreviousRecord;
                InFooterBar = true;

                trigger OnAction()
                begin
                    NextStep(true);
                end;
            }
            action("Next")
            {
                Caption = 'Next', Comment = 'Suivant';
                Enabled = NextEnable;
                Image = NextRecord;
                InFooterBar = true;

                trigger OnAction()
                begin
                    NextStep(false);
                end;
            }
            action(Finish)
            {
                Caption = 'Start Import 🚀', Comment = 'Lancer l''import 🚀';
                Enabled = FinishEnable;
                InFooterBar = true;

                trigger OnAction()
                begin
                    StartImport();
                end;
            }
        }
    }
    #endregion

    trigger OnInit()
    begin
        LoadBanners();
        Step := 1;
        EnableControls();
    end;

    trigger OnOpenPage()
    var
        ThreadMgt: codeunit "TOO Pipou Threads Mgt.";
    begin
        ThreadMgt.CheckThreadsRunning();
        if (Rec."Archive Name" <> '') then begin
            ArchiveName := rec."Archive Name";
            Step := 2; // skip introduction if a record is passed
        end;
        EnableControls();
#if ONPREM
        ImportMethod := ImportMethod::"DotNet SqlBulkCopy";
#endif
    end;

    local procedure ShowStep1()
    begin
        Step1Visible := true;
        NextEnable := true;
    end;

    local procedure ShowStep2()
    begin
        Step2Visible := true;
        NextEnable := true;
        BackEnable := true;
    end;

    local procedure ShowStep3()
    begin
        Step3Visible := true;
        NextEnable := true;
        BackEnable := true;
    end;

    local procedure ShowStep4()
    begin
        Step4Visible := true;
        NextEnable := true;
        BackEnable := true;
    end;

    local procedure ShowStep5()
    var
        ArchiveTables: Record "TOO Pipou Archive Tables";
    begin
        // Refresh company total data size
        ArchiveTables.SetRange("Archive ID", Rec."Archive ID");
        ArchiveTables.SetRange("Select For Import", true);
        CompanyTotalTables := ArchiveTables.Count();
        CompanyTotalDataSize := 0;
        CompanyTotalRecords := 0;
        if ArchiveTables.FindSet() then
            repeat
                CompanyTotalDataSize += ArchiveTables."Original Data Size (KB)";
                CompanyTotalRecords += ArchiveTables."No. of Records";
            until ArchiveTables.Next() = 0;

        Step5Visible := true;
        BackEnable := true;
        FinishEnable := true;
    end;

    local procedure NextStep(Backwards: Boolean)
    var
        ArchTables: Record "TOO Pipou Archive Tables";
    begin
        // Controls 2
        if (Step = 2) and not Backwards then
            if Rec."Archive Name" = '' then
                Error(ErrSelectArchiveFirst);
        // Controls 3
        if (Step = 3) and not Backwards then
            if Rec."Import Destination Company" = '' then
                Error(ErrSelectCompany);
        // Control 4
        if (Step = 4) and not Backwards then begin
            ArchTables.SetRange("Select For Import", true);
            if ArchTables.IsEmpty() then
                Error(ErrNoTableSelect);
        end;

        if Backwards then
            Step := Step - 1
        else
            Step := Step + 1;
        EnableControls();
    end;

    #region Launch Import
    local procedure StartImport()
    var
        Win: Dialog;
        WaitJobQueue: Label 'Starting Job Queue...';
        JobQueueEntry: Record "Job Queue Entry";
        Import: codeunit "TOO Pipou Import Multithreads";
        Logs: Record "TOO Pipou Import Log";
        RunBackgroundLbl: Label 'Would you like to run the import through Job Queue ? No will display the progress dialog.';
        ImportFinishedLbl: Label 'The import has completed in %1.\ Warnings : %2 \ Errors : %3 \ Open the log page ?';
        StartDT: DateTime;
        WarnCount, ErrCount : Integer;
    begin
        Rec."Import Use SQL Bulk" := (ImportMethod = ImportMethod::"DotNet SqlBulkCopy");
        Rec.Modify();

        if not Confirm(RunBackgroundLbl) then begin
            StartDT := CurrentDateTime;
            Import.MultiThreadImport(Rec, true);
            Logs.SetRange("Archive ID", Rec."Archive ID");
            Logs.SetFilter(SystemCreatedAt, '>=%1', StartDT);
            Logs.SetRange(Status, Logs.Status::Warning);
            WarnCount := Logs.Count();
            Logs.SetRange(Status, Logs.Status::Error);
            ErrCount := Logs.Count();
            Logs.SetRange(Status);
            SelectLatestVersion(); // clear instance cache to force SQL table re-read
            if Confirm(StrSubstNo(ImportFinishedLbl, CurrentDateTime - StartDT, WarnCount, ErrCount)) then
                Page.Run(Page::"TOO Pipou Import Logs", Logs);
        end else begin
            // Start Job Queue
            JobQueueEntry.ID := CreateGuid();
            JobQueueEntry."Object Type to Run" := JobQueueEntry."Object Type to Run"::Codeunit;
            JobQueueEntry."Object ID to Run" := Codeunit::"TOO Pipou Import Multithreads";
            JobQueueEntry."Recurring Job" := false;
            JobQueueEntry."Earliest Start Date/Time" := CurrentDateTime - 1000;
            JobQueueEntry."Record ID to Process" := Rec.RecordId;
            JobQueueEntry."Recurring Job" := False;
            JobQueueEntry.Status := JobQueueEntry.Status::"On Hold";
            JobQueueEntry.Insert();
            Commit();
            JobQueueEntry.Restart();
            Commit();
            // Open Archive Card with thread infos
            Win.Open(WaitJobQueue);
            Sleep(5000);
            Win.Close();
            Rec.Get(Rec."Archive Name", Rec."Archive ID");
            Page.Run(Page::"TOO Pipou Archive Card", Rec);
            CurrPage.Close();
        end;
    end;
    #endregion

    local procedure EnableControls()
    begin
        ResetControls();
        case Step of
            1:
                ShowStep1();
            2:
                ShowStep2();
            3:
                ShowStep3();
            4:
                ShowStep4();
            5:
                ShowStep5();
        end;
    end;

    local procedure ResetControls()
    begin
        Step1Visible := false;
        Step2Visible := false;
        Step3Visible := false;
        Step4Visible := false;
        Step5Visible := false;
        NextEnable := false;
        BackEnable := false;
        FinishEnable := false;
    end;

    local procedure LoadBanners()
    var
        MediaRepositoryDone: Record "Media Repository";
        MediaRepositoryStandard: Record "Media Repository";
    begin
        if MediaRepositoryStandard.Get('AssistedSetup-NoText-400px.png', Format(CurrentClientType())) and
            MediaRepositoryDone.Get('AssistedSetupDone-NoText-400px.png', Format(CurrentClientType()))
        then
            if MediaResourcesStandard.Get(MediaRepositoryStandard."Media Resources Ref") and MediaResourcesDone.Get(MediaRepositoryDone."Media Resources Ref") then;
    end;

    var
        ImportMethod: Option "AL Record.Insert","DotNet SqlBulkCopy";
        ArchiveName: Text;
        MediaResourcesDone: Record "Media Resources";
        MediaResourcesStandard: Record "Media Resources";
        BackEnable: Boolean;
        FinishEnable: Boolean;
        NextEnable: Boolean;
        Step1Visible: Boolean;
        Step2Visible: Boolean;
        Step3Visible: Boolean;
        Step4Visible: Boolean;
        Step5Visible: Boolean;
        Step: Integer;
        CompanyTotalDataSize: Integer;
        CompanyTotalTables: Integer;
        CompanyTotalRecords: Integer;
        UploadNewFileLbl: Label 'Upload a new file';
        OrLbl: Label '---- OR ----';
        SelectExistingFileLbl: Label 'Select existing uploaded file :';
        ErrSelectArchiveFirst: Label 'You must select an archive file to import data from.';
        ErrSelectCompany: Label 'You must select the destination company to import data to.';
        ErrNoTableSelect: Label 'You must select at least one table to import data from.';
}