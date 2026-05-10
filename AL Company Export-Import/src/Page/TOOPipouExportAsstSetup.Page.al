page 51008 "TOO Pipou Export Asst. Setup"
{
    ApplicationArea = All;
    Caption = 'Assisted company data export', Comment = 'Export données société assisté';
    PageType = NavigatePage;
    SourceTable = "TOO Pipou Archive"; // not temporary to allow catch of OnAfterGetRecord when the window dialog is closed
    UsageCategory = Lists;
    RefreshOnActivate = true;

    layout
    {
        area(Content)
        {
            // *** Top Banner ***
            #region Step 1 Intro
            group(Step1)
            {
                Caption = '', Locked = true;
                InstructionalText = '', Locked = true;
                Visible = Step1Visible;

                group(Group10)
                {
                    Caption = 'Let''s Go', Comment = 'C''est parti';
                    InstructionalText = 'Welcome to the Pipou Company data export wizard. Fill in the informations at each step until you see the “Start Export” button.', Comment = 'Bienvenue dans l''assistant d''export de données sociétés. Remplissez les informations à chaque étape jusqu''à voir le bouton "Lancer l''export".';
                    //
                }
                group(Group11)
                {
                    Caption = '', Locked = true;
                    InstructionalText = 'The export process will start once you press Finish in last step.', Comment = 'Le processus d''export débutera après avoir cliquer sur le bouton "Terminer" en dermière étape.';
                }
                group(Group12)
                {
                    Caption = 'Click on "Next" to begin.', Comment = 'Cliquer sur "Suivant" pour commencer.';
                    InstructionalText = '', Locked = true;
                }
            }
            #endregion
            #region Step2 Company
            group(Step2)
            {
                Caption = 'Company', Comment = 'Choix de la société';
                InstructionalText = 'Specify the company to export data from.', Comment = 'Spécifier la société depuis la quel vous souhaitez exporter les données.';
                Visible = Step2Visible;

                field("Export Company Name"; ExportCompanyName)
                {
                    ApplicationArea = Basic, Suite;
                    AssistEdit = false;
                    Caption = 'Export Company Name', Comment = 'Nom de la société à exporter';
                    Importance = Promoted;
                    ShowMandatory = true;
                    ToolTip = 'Specify the company to export data from.', Comment = 'Spécifier la société depuis la quel vous souhaitez exporter les données.';
                    TableRelation = Company.Name;
                    NotBlank = true;
                }
            }
            #endregion
            #region Step 3 Data
            group(Step3)
            {
                Caption = 'Data to export', Comment = 'Choix des données à exporter';
                InstructionalText = 'Specify what table to export and how to handle classified data.', Comment = 'Spécifier quelle table exporter et comment gérer les données classifiées.';
                Visible = Step3Visible;

                field(ClassifiedDataHandling; ClassifiedDataHandling)
                {
                    Caption = 'Classified Data Handling', Comment = 'Traitement des données sensibles';
                    ApplicationArea = All;
                    ToolTip = 'Specify how to handle data such as Name and Email, where Dataclassification=CustomerContent';
                }
                field(IncludeAuditFields; IncludeAuditFields)
                {
                    Caption = 'Include Audit Fields', Comment = 'Inclure les champs Audit';
                    ApplicationArea = All;
                    ToolTip = 'Specify if audit fields (SystemCreated and  Modified On and By). Note that thoses field can only be imported OnPremise through SQL.';
                }
                field(IncludeGlobalData; IncludeGlobalData)
                {
                    Caption = 'Include Global data', Comment = 'Inclure données globales';
                    ApplicationArea = All;
                    ToolTip = 'Specify if table with datapercompany = false shall be exported. Such data contain users, permissions sets, profile, peronnalizations and so on.';
                }
                field(IncludeLogsTables; IncludeLogsTables)
                {
                    Caption = 'Include Logs tables', Comment = 'Inclure les logs';
                    ToolTip = 'Specify to include all table with name containinag " log" such as job queue entry log. This data may not be relevent for simple use case scenario and could be skipped to reduce file size and fasten export.';
                    ApplicationArea = All;
                }
                field(IncludeArchiveTables; IncludeArchiveTables)
                {
                    Caption = 'Include Archives tables', Comment = 'Inclure les archives';
                    ToolTip = 'Specify to include all table with name containinag " archive" such as workflow event archives or purchase/sales document archives. This data may not be relevent for simple use case or test scenario, and could be skipped to reduce file size and fasten export.';
                    ApplicationArea = All;
                }
                field("Diff. Export Start DT"; TempArchive."Diff. Export Start DT")
                {
                    Caption = 'Differential Export From DT', Comment = 'Export differentiel depuis Date heure';
                    ToolTip = 'Specify to export only date created or modified after specified date time. The option may be used to update a company that were already imported with only newly created data, avoiding a full import.';
                    ApplicationArea = All;
                }
            }
            #endregion

            #region Step 4 Tables
            group(Step4)
            {
                Caption = 'Tables to export', Comment = 'Tables a exporter';
                InstructionalText = 'Review and modify the list of table data to export.', Comment = 'Passer en revue la liste des tables a exporter et modifier la liste si besoin.';
                Visible = Step4Visible;

                part(TableList; "TOO Pipou Export Tables Sub")
                {
                    UpdatePropagation = Both;
                }
            }
            #endregion

            #region Step 5 Format
            group(Step5)
            {
                Caption = 'File Format', Comment = 'Format du fichier';
                InstructionalText = 'Specify the data format options and compression method. Default option are the best suited for most case.', Comment = 'Spécifiez les options de format de données et la méthode de compression. Les options par défaut sont optimales dans la plupart des cas.';
                Visible = Step5Visible;

                field(PreferedCompressionMode; PreferedCompressionMode)
                {
                    Caption = 'Prefered compression method';
                    ValuesAllowed = Gzip, zstandard, libbsc, "Auto (On-Premise)", "Auto (Cloud)";
                    ApplicationArea = All;
                    ToolTip = 'Compression and encoding options used. "Auto" will use the best combination for speed and compression balance. zStandard and LibBSC are more efficient but only supported On-premise. LibBSC offer best overall compression ratio with high processing speed.';

                    trigger OnValidate()
                    begin
                        if PreferedCompressionMode = PreferedCompressionMode::"Auto (On-Premise)" then begin
#if not ONPREM
                            Error('This export format is not supported on SaaS environnement.');
#endif
                            IncludeAuditFields := true;
                            PreferedCompressionMode := PreferedCompressionMode::"Auto (On-Premise)";
                            // 75 Mb
                            MaxChunkSize := 75 * 1024 * 1024;
                            MaxChunkSizeOption := MaxChunkSizeOption::"75 MB";

                        end;
                        if PreferedCompressionMode = PreferedCompressionMode::"Auto (Cloud)" then begin
                            IncludeAuditFields := false;
                            PreferedCompressionMode := PreferedCompressionMode::"Auto (Cloud)";
                            // 200 Mb
                            MaxChunkSize := 200 * 1024 * 1024;
                            MaxChunkSizeOption := MaxChunkSizeOption::"200 MB";
                        end;

                        AdvancedEncodingVisible := not (PreferedCompressionMode in [PreferedCompressionMode::"Auto (Cloud)", PreferedCompressionMode::"Auto (On-Premise)"]);
                    end;
                }
                group(Manual)
                {
                    Caption = 'Advanced Options';
                    Visible = AdvancedEncodingVisible;

                    field(EnableColumnTranscode; EnableColumnTranscode)
                    {
                        Caption = 'Enable Column transcoding';
                        ToolTip = 'Specify to enable per column storage (parquet like format). Allow to exclude empty column and improve overall compression ratio.';
                        ApplicationArea = all;
                    }
                    field(MaxChunkSizeOption; MaxChunkSizeOption)
                    {
                        Caption = 'Max. Chunk size in MB';
                        ToolTip = 'Maximum data size before it is compressed and a new file is created. Larger chunk size consume more RAM but may slightly improve compression ratio.';
                        ApplicationArea = all;

                        trigger OnValidate()
                        begin
                            case MaxChunkSizeOption of
                                MaxChunkSizeOption::"50 Mb":
                                    MaxChunkSize := 50 * 1024 * 1024;
                                MaxChunkSizeOption::"75 Mb":
                                    MaxChunkSize := 75 * 1024 * 1024;
                                MaxChunkSizeOption::"100 Mb":
                                    MaxChunkSize := 100 * 1024 * 1024;
                                MaxChunkSizeOption::"150 Mb":
                                    MaxChunkSize := 150 * 1024 * 1024;
                                MaxChunkSizeOption::"200 Mb":
                                    MaxChunkSize := 200 * 1024 * 1024;
                            end;
                        end;
                    }
                    field(BlobMaxSizeOption; BlobMaxSizeOption)
                    {
                        Caption = 'Max. Allowed Blob Size';
                        ToolTip = 'Specify the maximum Blob length exported. Larger Blob will be exported as empty.';
                        ApplicationArea = all;

                        trigger OnValidate()
                        begin
                            case BlobMaxSizeOption of
                                BlobMaxSizeOption::"5 MB":
                                    BlobMaxSize := 5 * 1024 * 1024;
                                BlobMaxSizeOption::"10 Mb":
                                    BlobMaxSize := 10 * 1024 * 1024;
                                BlobMaxSizeOption::"25 MB":
                                    BlobMaxSize := 25 * 1024 * 1024;
                                BlobMaxSizeOption::"50 MB":
                                    BlobMaxSize := 50 * 1024 * 1024;
                            end;
                        end;
                    }
                }
            }
            #endregion

            #region Step 6 Export

            group(Step6)
            {
                Caption = 'Run the export !', Comment = 'Lancer l''export !';
                InstructionalText = 'All parameters were set. You can review the information bellow. Click "Start Export" to launch the process of exporting all data in a file. The file will be downloaded in you your user downlaod folder once finished.',
                        Comment = 'Tous les paramètres ont été saisis. Cliquez sur "Lancer l''export" pour demarrer le processus d''export. Le fichier sera telecharger automatiquement dans votre repertoire Download en fin de traitement.';
                Visible = Step6Visible;

                group(Group61)
                {
                    Caption = 'Summary', Comment = 'Recapitulatif';

                    field("Export Company Name 2"; ExportCompanyName)
                    {
                        Caption = 'Export Company Name', Comment = 'Nom de la société à exporter';
                        Editable = false;
                    }
                    field(ClassifiedDataHandling2; ClassifiedDataHandling)
                    {
                        Caption = 'Classified Data Handling', Comment = 'Traitement des données sensibles';
                        Editable = false;
                    }
                    field(NoTables; CompanyTotalTables)
                    {
                        Caption = 'Total Number of Tables';
                        Editable = false;
                    }
                    field(NoRecs; CompanyTotalRecords)
                    {
                        Caption = 'Total Number of Records';
                        Editable = false;
                    }
                }
                group(Group62)
                {
                    Caption = 'Multithreading', Comment = 'Exécution parallèle';

                    field(MultiThreading; TempArchive."Number of Threads")
                    {
                        Caption = 'Number of Threads', Comment = 'Nombre de thread';
                        NotBlank = true;
                        MinValue = 1;
                        MaxValue = 6;
                    }
                }
            }
            #endregion
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
                Caption = 'Start Export 🚀', Comment = 'Lancer l''export 🚀';
                Enabled = FinishEnable;
                InFooterBar = true;

                trigger OnAction()
                var
                    Archive: Record "TOO Pipou Archive";
                begin
                    PressedExport := true;
                    StartExport();
                    Rec.SetRange("Archive ID", TempArchive."Archive ID");
                    if Rec.FindFirst() then
                        Page.Run(Page::"TOO Pipou Archive Card", Rec);
                    CurrPage.Close();
                end;
            }
        }
    }
    #endregion

    trigger OnInit()
    begin
        Step := 1;
        EnableControls();
        ArchiveGUID := CreateGuid();
        TempArchive."Archive ID" := ArchiveGUID;
        Rec.Init();
        Rec."Archive ID" := ArchiveGUID;
        TempArchive."Number of Threads" := 4;
        TempArchive.Insert();
        // Init Default option
        BlobMaxSize := 50 * 1024 * 1024; // 50 Mb
        BlobMaxSizeOption := BlobMaxSizeOption::"50 MB";
        ClassifiedDataHandling := ClassifiedDataHandling::Keep;
        EnableColumnTranscode := true;
#if ONPREM
        IncludeAuditFields := true;
        PreferedCompressionMode := PreferedCompressionMode::"Auto (On-Premise)";
        // 150 Mb
        MaxChunkSize := 150 * 1024 * 1024;
        MaxChunkSizeOption := MaxChunkSizeOption::"100 MB";
#else
        IncludeAuditFields := false;
        PreferedCompressionMode := PreferedCompressionMode::"Auto (Cloud)";
        // 200 Mb
        MaxChunkSize := 200 * 1024 * 1024;
        MaxChunkSizeOption := MaxChunkSizeOption::"200 MB";
#endif
    end;

    trigger OnOpenPage()
    var
        ThreadMgt: codeunit "TOO Pipou Threads Mgt.";
        WriteInsideTryFunctionEnabled: Codeunit "TOO WriteInsideTryEnabled";
        WriteInTryMusTBeEnabled: Label 'The service instance does not allow transaction inside TryFunction, this must be enabled to run this process.\Use Business Central Administration Shell to set this configuration :\Powershell:\Set-NavServerConfiguration InstanceName -KeyName DisableWriteInsideTryFunctions -KeyValue false \-\Restarting Business Central service is required after this change.';
    begin
        if not WriteInsideTryFunctionEnabled.Run() then
            Error(WriteInTryMusTBeEnabled);
        ThreadMgt.CheckThreadsRunning();
    end;

    trigger OnAfterGetCurrRecord()
    var
        Archive: record "TOO Pipou Archive";
    begin
        if (step = 6) and PressedExport then begin
            Rec.SetRange("Archive ID", TempArchive."Archive ID");
            if Rec.FindFirst() then begin
                Page.RunModal(Page::"TOO Pipou Archive Card", Rec);
                CurrPage.Close();
            end;
        end;
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
        if not TableListCreated then begin
            CreateTablesLists();
            TableListCreated := true;
        end;

        Step4Visible := true;
        NextEnable := true;
        BackEnable := true;
    end;

    local procedure ShowStep5()
    begin
        Step5Visible := true;
        NextEnable := true;
        BackEnable := true;
    end;

    local procedure ShowStep6()
    var
        ArchiveTables: Record "TOO Pipou Archive Tables";
    begin
        // Refresh company total data size
        TempArchiveTables.SetFilter("No. of Records", '>0');
        CompanyTotalTables := TempArchiveTables.Count();
        CompanyTotalRecords := 0;
        TempArchiveTables.CalcSums("No. of Records");
        CompanyTotalRecords += TempArchiveTables."No. of Records";

        Step6Visible := true;
        BackEnable := true;
        FinishEnable := true;
    end;

    local procedure NextStep(Backwards: Boolean)
    begin
        if (Step = 2) and not Backwards then
            if ExportCompanyName = '' then
                Error('You must define a company to export data from.');
        if Backwards then
            Step := Step - 1
        else
            Step := Step + 1;
        EnableControls();
    end;

    #region Gen.Tables
    local procedure CreateTablesLists()
    var
        TableMeta: Record "Table Metadata";
        Fields: Record Field;
        Win: Dialog;
        I: Integer;
        RecRef: RecordRef;
        NoOfRec: Integer;
#if ONPREM
        TableInfo: Record "Table Information";
#endif
    begin
        Win.Open('Generating table and field definition list... \#1########');

#if ONPREM
        // === ON-PREMISES: Use Table Information (faster record count) ===
        FilterTableInfo(TableMeta, not IncludeLogsTables, not IncludeArchiveTables);
        TableInfo.SetLoadFields("No. of Records", "Table No.", "Table Name");
        TableInfo.SetRange("Company Name", ExportCompanyName);
        TableInfo.SetFilter("Table No.", TableMeta.GetFilter(ID));
        TableInfo.SetFilter("Table Name", TableMeta.GetFilter(Name));
        CompanyTotalTables := TableInfo.Count();

        if TableInfo.FindSet() then
            repeat
                if (TableInfo."Table No." < 2000000000) then begin   // Skip most system tables
                                                                     // Search fields (same logic)
                    Fields.SetRange(TableNo, TableInfo."Table No.");
                    if IncludeAuditFields then
                        Fields.SetFilter("No.", '<>2000000000') // only exclude the systemID, keep audits
                    else
                        Fields.SetFilter("No.", '<2000000000');

                    Fields.SetRange(Class, Fields.Class::Normal);
                    Fields.SetRange(ObsoleteState, Fields.ObsoleteState::No);
                    Fields.SetRange(Enabled, true);

                    if Fields.FindSet() then begin
                        if TableInfo."No. of Records" > 0 then begin
                            TableMeta.Get(TableInfo."Table No.");
                            StoreTableMeta(TableMeta, TableInfo."No. of Records");
                            repeat
                                StoreFieldMeta(Fields);
                            until Fields.Next() = 0;
                        end;
                    end;
                end;

                I += 1;
                Win.Update(1, ProgressBar(I / CompanyTotalTables));
            until TableInfo.Next() = 0;

#else
        // === CLOUD / SaaS: Use Table Metadata (only supported option) ===
        FilterTableInfo(TableMeta, not IncludeLogsTables, not IncludeArchiveTables);
        CompanyTotalTables := TableMeta.Count();

        if TableMeta.FindSet() then
            repeat
                if (TableMeta.ID < 2000000000) then begin
                    Fields.SetRange(TableNo, TableMeta.ID);
                    if IncludeAuditFields then
                        Fields.SetFilter("No.", '<>2000000000')
                    else
                        Fields.SetFilter("No.", '<2000000000');

                    Fields.SetRange(Class, Fields.Class::Normal);
                    Fields.SetRange(ObsoleteState, Fields.ObsoleteState::No);
                    Fields.SetRange(Enabled, true);

                    if Fields.FindSet() then begin
                        RecRef.Open(TableMeta.ID, false, ExportCompanyName);
                        NoOfRec := RecRef.Count();
                        RecRef.Close();

                        if NoOfRec > 0 then begin
                            StoreTableMeta(TableMeta, NoOfRec);
                            repeat
                                StoreFieldMeta(Fields);
                            until Fields.Next() = 0;
                        end;
                    end;
                end;

                I += 1;
                Win.Update(1, ProgressBar(I / CompanyTotalTables));
            until TableMeta.Next() = 0;
#endif
        CurrPage.TableList.Page.SetTempTables(TempArchiveTables);
        CurrPage.TableList.Page.SetTempFields(TempArchiveTableFields);
        Win.Close();
    end;

    local procedure FilterTableInfo(var Tables: Record "Table Metadata"; ExclLogsTables: Boolean; ExclArchiveTables: Boolean)
    var
        NameFilter: Text;
        IDFilter: Text;
    begin
        // Exclude Self
        IDFilter := StrSubstNo('<>%1&<>%2&<>%3&<>%4&<>%5&<>%6&<>%7&<>%8&<>%9&<>%10&<>%11&<>%12&<>%13&<>%14&<>%15', Database::"TOO Pipou Archive", Database::"TOO Pipou Archive Tables", Database::"TOO Pipou Archive Fields", Database::"TOO Pipou Archive Files", Database::"TOO Pipou Import Log", database::"TOO Pipou Thread", Database::"Config. Package Data", Database::"Config. Package Error", Database::"Config. Package Record", Database::"Configuration Package File", Database::"Config. Record For Processing", database::"Error Message", database::"Data Migration Error", Database::Session, Database::"Session Event");
        // Exclude Buffers
        NameFilter := '<>* Buffer';
        // Exclude Logs       
        if ExclLogsTables then begin
            NameFilter += '&<>* Log&<>* log&<>* Logs&<>* logs&<>*Log Entry';
            IDFilter += StrSubstNo('&<>%1&<>%2&<>%3', database::"Config. Package Data", database::"Config. Package Error", Database::"Config. Package Record");
        end;
        // Exclude Archive
        if ExclArchiveTables then begin
            NameFilter += '&<>* Archive*&<>* archive*&<>* Archives*&<>* archives*';
            IDFilter += StrSubstNo('&<>%1&<>%2&<>%3&<>%4', database::"Sent Email", database::"Sent Notification Entry", database::"Posted Gen. Journal Batch", database::"Posted Gen. Journal Line");
            IDFilter += StrSubstNo('&<>%1&<>%2&<>%3', database::"Config. Package Data", database::"Config. Package Error", Database::"Config. Package Record");
        end;
        // Exclude not importable systems/virtual tables
        IDFilter += StrSubstNo('&<>%1&<>%2&<>%3&<>%4', 150 /*"Signup Context Values"*/, 2000000255 /*"Signup Context"*/, 2610 /*"Feature Data Update Status"*/, 9999 /*"Upgrade Tags"*/);

        Tables.Setfilter("Name", NameFilter);
        Tables.SetFilter(ID, IDFilter);
        Tables.SetRange(DataIsExternal, false);
    end;
    #endregion

    #region Launch Export
    local procedure StartExport()
    var
        Win: Dialog;
        CreatingArch: Label 'Creating archive metadata...';
        Exportcompleted: Label 'The export of company %1 has been completed in %2.\ \Total Data Size : %3\Total Compressed Size : %4';
        NothingToExport: Label 'There were no data found to export in given company. If you provide a date time for differential export, make sure records were created after this date.';
        ProcessingStart: DateTime;
        PipouExport: Codeunit "TOO Pipou Export Data";
        RecRef: RecordRef;
        ArchiveTables: Record "TOO Pipou Archive Tables";
        ArchiveTablesFields: Record "TOO Pipou Archive Fields";
    begin
        Win.Open(CreatingArch);
        // Create archive record
        Rec.Init();
        Rec."Archive ID" := ArchiveGUID;
        Rec."Archive Sequence No." := 1;
        // date format 9 : 2025-09-13T18:20:54.1000000Z
        if PreferedCompressionMode in [PreferedCompressionMode::"Auto (On-Premise)", PreferedCompressionMode::libbsc, PreferedCompressionMode::zStandard, PreferedCompressionMode::MCMX] then
            Rec."Archive Name" := ExportCompanyName + '-' + format(CurrentDateTime, 0, 9).Substring(1, 10).Replace(':', '.') + ' (OnPrem).zip'
        else
            Rec."Archive Name" := ExportCompanyName + '-' + format(CurrentDateTime, 0, 9).Substring(1, 10).Replace(':', '.') + '.zip';
        Rec."Exported From Company" := ExportCompanyName;
        Rec."Exported Date Time" := CurrentDateTime;
        Rec."Number of Threads" := TempArchive."Number of Threads";
        Rec."Prefered Compression Mode" := PreferedCompressionMode;
        Rec."Blob Max Size" := BlobMaxSize;
        Rec."Chunk Max Size" := MaxChunkSize;
        Rec."Diff. Export Start DT" := TempArchive."Diff. Export Start DT";
        Rec."Process Status" := Rec."Process Status"::"⌛ Exporting";
        Rec.ClassifiedDataHandling := ClassifiedDataHandling;
        Rec."Enable Columns Transcoding" := EnableColumnTranscode;
        // Set the actual number of tables and record after user selection
        TempArchiveTables.Reset();
        Rec."Total Tables" := TempArchiveTables.Count();
        TempArchiveTables.CalcSums("No. of Records");
        Rec."Total Records" := TempArchiveTables."No. of Records";

        // Store the archive informations
        if not Rec.Insert(true) then
            Rec.Modify(); // if second time pressing export

        // Store Tables
        ArchiveTables.SetRange("Archive ID");
        ArchiveTables.DeleteAll(); // if second time pressing export
        TempArchiveTables.FindSet();
        repeat
            ArchiveTables.TransferFields(TempArchiveTables, false);
            ArchiveTables."Archive ID" := ArchiveGUID;
            ArchiveTables."Table ID" := TempArchiveTables."Table ID";
            ArchiveTables.Insert();
        until TempArchiveTables.Next() = 0;

        // Store Fields
        ArchiveTablesFields.SetRange("Archive ID");
        ArchiveTablesFields.DeleteAll(); // if second time pressing export
        TempArchiveTableFields.FindSet();
        repeat
            ArchiveTablesFields.TransferFields(TempArchiveTableFields, false);
            ArchiveTablesFields."Archive ID" := ArchiveGUID;
            ArchiveTablesFields."Table ID" := TempArchiveTableFields."Table ID";
            ArchiveTablesFields."Field ID" := TempArchiveTableFields."Field ID";
            ArchiveTablesFields.Insert();
        until TempArchiveTableFields.Next() = 0;
        Commit();
        Win.Close();

        // Run exports
        ProcessingStart := CurrentDateTime;
        PipouExport.MultiThreadExport(Rec);
        Rec.Get(Rec."Archive Name", Rec."Archive ID");
        if Rec."No. Files" = 0 then
            Error(NothingToExport);

        PressedExport := false; // disable catching dialog closed

        // Download
        Rec.DownloadArchiveFile();

        Message(Exportcompleted, ExportCompanyName, CurrentDateTime - ProcessingStart, Format(round(Rec."Files Size (KB)" / 1024, 0.01)) + ' Mb', Format(round(Rec."Files Compressed Size (KB)" / 1024, 0.01)) + ' Mb');
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
            6:
                ShowStep6();
        end;
    end;

    local procedure ResetControls()
    begin
        Step1Visible := false;
        Step2Visible := false;
        Step3Visible := false;
        Step4Visible := false;
        Step5Visible := false;
        Step6Visible := false;
        NextEnable := false;
        BackEnable := false;
        FinishEnable := false;
    end;

    procedure ProgressBar(ProgressPercent: Decimal) AsciiResult: Text
    var
        i: Integer;
        ProgressChar: Integer;
    begin
        ProgressChar := Round(ProgressPercent * 24, 1, '<') + 1;
        for i := 1 to 24 do begin
            if i < ProgressChar then
                AsciiResult += '▰'
            else
                if i = ProgressChar then
                    AsciiResult += '▴'
                else
                    AsciiResult += '▱';
            if i = 12 then // half of 25
                AsciiResult += Format(Round(ProgressPercent * 100, 1)).PadLeft(2, '0') + '%';
        end;
    end;

    #region Store Meta
    procedure StoreTableMeta(var TableMeta: Record "Table Metadata"; NoOfRecords: Integer)
    begin
        TempArchiveTables.Init();
        TempArchiveTables."Archive ID" := TempArchive."Archive ID";
        TempArchiveTables.DataPerCompany := TableMeta.DataPerCompany;
        TempArchiveTables."Table DataClassification" := TableMeta.DataClassification;
        TempArchiveTables."No. of Records" := NoOfRecords;
        TempArchiveTables."Table Caption" := TableMeta.Caption;
        TempArchiveTables."Table Name" := TableMeta.Name;
        TempArchiveTables."Table ID" := TableMeta.ID;
        TempArchiveTables.Insert();
    end;

    procedure StoreFieldMeta(var FieldInfo: Record Field)
    begin
        TempArchiveTableFields.Init();
        TempArchiveTableFields."Archive ID" := TempArchive."Archive ID";
        TempArchiveTableFields."Table ID" := FieldInfo.TableNo;
        TempArchiveTableFields."Field ID" := FieldInfo."No.";
        TempArchiveTableFields."Field Caption" := FieldInfo."Field Caption";
        TempArchiveTableFields."Field Name" := FieldInfo.FieldName;
        TempArchiveTableFields."Field DataClassification" := FieldInfo.DataClassification;
        TempArchiveTableFields."Field Type" := FieldInfo.Type;
        TempArchiveTableFields."Field Type Name" := FieldInfo."Type Name";
        TempArchiveTableFields."Max Length" := FieldInfo.Len;
        TempArchiveTableFields."Part of Primary Key" := FieldInfo.IsPartOfPrimaryKey;
        TempArchiveTableFields.Insert();
    end;
    #endregion

    var
        PressedExport: Boolean;
        BackEnable: Boolean;
        FinishEnable: Boolean;
        NextEnable: Boolean;
        Step1Visible: Boolean;
        Step2Visible: Boolean;
        Step3Visible: Boolean;
        Step4Visible: Boolean;
        Step5Visible: Boolean;
        Step6Visible: Boolean;
        Step: Integer;
        TableListCreated: Boolean;
        ExportCompanyName: Text[30];
        ClassifiedDataHandling: Option "Keep","Empty";
        IncludeAuditFields: Boolean;
        IncludeGlobalData: Boolean;
        IncludeLogsTables: Boolean;
        IncludeArchiveTables: Boolean;
        BlobMaxSizeOption: Option "5 MB","10 MB","25 MB","50 MB";
        BlobMaxSize: Integer;
        PreferedCompressionMode: enum "TOO Compression Algo.";
        MaxChunkSize: Integer; // in bytes, default is 200MB
        MaxChunkSizeOption: Option "50 MB","75 MB","100 MB","150 MB","200 MB";
        CompanyTotalTables: Integer;
        CompanyTotalRecords: Integer;
        ArchiveGUID: Guid; // generate before Archive rec for table and field list
        EnableColumnTranscode: Boolean;
        AdvancedEncodingVisible: Boolean;
        TempArchiveTables: Record "TOO Pipou Archive Tables" temporary;
        TempArchiveTableFields: Record "TOO Pipou Archive Fields" temporary;
        TempArchive: Record "TOO Pipou Archive" temporary;
}