table 51006 "TOO Pipou Archive"
{
    DataClassification = CustomerContent;
    LookupPageId = "TOO Pipou Archive Card";
    DrillDownPageId = "TOO Pipou Archive Card";
    DataPerCompany = false;


    fields
    {
        field(1; "Entry No."; Integer)
        {
        }
        field(10; "Archive Name"; Text[150])
        {
        }
        field(15; "Archive ID"; Guid)
        {

        }
        field(20; "Archive Sequence No."; Integer)
        {
        }
        field(25; "Exported Date Time"; DateTime)
        {

        }
        field(26; "Exported From Company"; Text[30])
        {

        }
        field(35; "Import Destination Company"; Text[30])
        {
            TableRelation = Company.Name;

            trigger OnValidate()
            var
                Chunks: Record "TOO Pipou Archive Files";
            begin
                Chunks.SetRange("Archive Name", Rec."Archive Name");
                Chunks.SetRange("Archive ID", Rec."Archive ID");
                Chunks.SetRange(Imported, true);
                if not Chunks.IsEmpty() then
                    Error('You can not change the destination company when data were already marked as imported.');
            end;
        }
        field(200; "Files Compressed Size (KB)"; Decimal)
        {

        }
        field(210; "Files Size (KB)"; Decimal)
        {

        }
        field(220; "Compression Ratio (%)"; Decimal)
        {

        }
        field(230; "Total Records"; Integer)
        {

        }
        field(240; "Total Tables"; Integer)
        {

        }
        field(320; "Enable Columns Transcoding"; Boolean)
        {

        }
        field(400; "Metadata Json Content"; Blob)
        {

        }
        field(450; "No. Tables"; Integer)
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = count("TOO Pipou Archive Tables" where("Archive ID" = field("Archive ID")));
        }
        field(500; "No. Files"; Integer)
        {

        }
        field(510; "Imported Files"; Integer)
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = count("TOO Pipou Archive Files" where("Archive Name" = field("Archive Name"), "Archive ID" = field("Archive ID"), Imported = const(true)));
        }
        field(600; "Import Warning / Error"; Integer)
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = count("TOO Pipou Import Log" where("Archive Name" = field("Archive Name"), "Archive ID" = field("Archive ID")));
        }
        #region Export Options
        field(700; ClassifiedDataHandling; Option)
        {
            OptionMembers = "Keep","Empty";
        }
        field(710; "Blob Max Size"; Integer) { }
        field(720; "Chunk Max Size"; Integer) { }
        field(730; "Prefered Compression Mode"; enum "TOO Compression Algo.") { }
        field(740; "Diff. Export Start DT"; DateTime) { }
        #endregion

        #region Import Option
        field(800; DeleteData; Boolean)
        {
            Caption = 'Truncate Table';
        }
        field(830; "Import Use SQL Bulk"; Boolean) { }
        #endregion

        field(1000; "Process Status"; Option)
        {
            OptionMembers = " ","⌛ Exporting","⌛ Importing","✅ Partially Imported","✅ Imported","✅ Exported";
        }
        field(1001; "Process Started At"; DateTime) { }
        field(1002; "Size To Process (KB)"; Integer) { }
        field(1010; "Data Size Proceed"; Decimal) { }
        field(1090; "Number of Threads"; Integer) { }
    }

    keys
    {
        key(Key1; "Archive Name", "Archive ID")
        {
            Clustered = true;
        }
    }

    trigger OnDelete()
    var
        ArchTable: Record "TOO Pipou Archive Tables";
        ArchFields: Record "TOO Pipou Archive Fields";
        ArchFile: Record "TOO Pipou Archive Files";
        ArchLogs: Record "TOO Pipou Import Log";
        ConfirmLbl: label 'Archive %1 have been partially imported, removing it will erase the logs and pending data that were not imported yet. Continue ?';
    begin
        if GuiAllowed then
            if Rec."Process Status" = Rec."Process Status"::"✅ Partially Imported" then
                if not Confirm(StrSubstNo(ConfirmLbl, Rec."Archive Name")) then
                    Error('');

        if not Rec.IsTemporary then begin
            ArchFile.SetRange("Archive ID", Rec."Archive ID");
            ArchFile.DeleteAll();
            ArchLogs.SetRange("Archive ID", Rec."Archive ID");
            ArchLogs.DeleteAll();
            ArchTable.SetRange("Archive ID", Rec."Archive ID");
            ArchTable.DeleteAll();
            ArchFields.SetRange("Archive ID", Rec."Archive ID");
            ArchFields.DeleteAll();
        end;
    end;

    #region Import Archive
    procedure UploadArchiveFileDialog(): Boolean
    var
        ImportedfileName: Text;
        UploadJS: Page "TOO Upload File JS";
        File: File;
#if ONPREM
        SelectFilePage: Page "TOO Select File Path";
#endif
        FileNameHelper: Codeunit "File Management";
        TempBlob: codeunit "Temp Blob";
        DataArchiveInStr: InStream;
        ChooseUploadLbl: Label 'Select an uploading option according the archive file size';
        UploadOptionLbl: Label 'Quick upload from client (Fast. Up to 350 MB), Large file upload from client (Slow. Up to 2 GB), Large file upload from server system path file (Fast. Up to 2 GB)';
    begin
        case StrMenu(UploadOptionLbl, 0, ChooseUploadLbl) of
            1:// Normal upload
                begin
                    // Upload file (Max 350 MB)
                    TempBlob.CreateInStream(DataArchiveInStr);
                    UploadIntoStream('Import', '', '', ImportedfileName, DataArchiveInStr);
                    exit(Rec.ImportArchiveFile(ImportedfileName, DataArchiveInStr));
                end;

            2:// JS Chunk Upload
                begin
                    // Upload file (Max 350 MB)
                    UploadJS.LookupMode(true);
                    if not (UploadJS.RunModal() in [Action::LookupOK, Action::OK, Action::Yes]) then
                        exit;
                    // Import
                    UploadJS.GetInStream(ImportedfileName, DataArchiveInStr);
                    exit(Rec.ImportArchiveFile(ImportedfileName, DataArchiveInStr));
                end;

            3: // file system upload
                begin
#if ONPREM
                    // Select file path
                    SelectFilePage.LookupMode(true);
                    if not (SelectFilePage.RunModal() in [Action::LookupOK, Action::OK, Action::Yes]) then
                        exit;

                    // Open File
                    File.Open(SelectFilePage.GetFilePath());
                    ImportedfileName := FileNameHelper.GetFileName(SelectFilePage.GetFilePath());
                    File.CreateInStream(DataArchiveInStr);

                    // Import
                    exit(Rec.ImportArchiveFile(ImportedfileName, DataArchiveInStr));
                    File.Close();
#endif
                end;
        end;
    end;

    procedure ImportArchiveFile(ArchiveName: Text; var DataArchiveInStr: InStream): Boolean
    var
        IsMetaGZ: Boolean;
        IsTar: Boolean;
        TarArchiveMgt: Codeunit "TOO TAR Mgt.";
        ZipMgt: Codeunit "Data Compression";
        EntryList: List of [Text];
        ProgressLbl: Label 'Extracting data files from archive... \ #1######## \ #2##########';
        ReadingMetaLbl: Label 'Reading archive meta data...';
        OutStr: OutStream;
        InStr: InStream;
        FileNo: Integer;
        ChunkData: record "TOO Pipou Archive Files";
        Window: Dialog;
        TempBlob: Codeunit "Temp Blob";
        ArchiveMgt: Codeunit "TOO Pipou Archive Meta Mgt.";
    begin
        // Check base archive format (either ZIP or TAR)
        if not ZipMgt.IsZip(DataArchiveInStr) and not TarArchiveMgt.IsTar(DataArchiveInStr) then
            Error('The file format is not recognized. Archive file must be packed in TAR or ZIP format.');

        // Open Archive
        if GuiAllowed then
            Window.Open(ReadingMetaLbl);
        IsTar := TarArchiveMgt.IsTAR(DataArchiveInStr);
        if IsTar then begin
            TarArchiveMgt.OpenTarArchive(DataArchiveInStr);
            TarArchiveMgt.GetEntryList(EntryList);
        end else begin
            ZipMgt.OpenZipArchive(DataArchiveInStr, false);
            ZipMgt.GetEntryList(EntryList);
        end;

        // Load Meta data (JSON)
        if (EntryList.IndexOf('datameta.json') = 0) and (EntryList.IndexOf('datameta.json.gz') = 0) then
            Error('Format not recognized - the archive does not contain "datameta.json" or "datameta.json.gz" file.');
        Rec.Init();
        Rec."Archive Name" := ArchiveName;
        Rec."Metadata Json Content".CreateOutStream(OutStr);
        IsMetaGZ := EntryList.IndexOf('datameta.json.gz') > 0;
        if IsTar then begin
            if IsMetaGZ then
                TarArchiveMgt.ExtractEntry('datameta.json.gz', OutStr)
            else
                TarArchiveMgt.ExtractEntry('datameta.json', OutStr)
        end else begin
            if IsMetaGZ then
                ZipMgt.ExtractEntry('datameta.json.gz', OutStr)
            else
                ZipMgt.ExtractEntry('datameta.json', OutStr);
        end;

        // Default import options
        Rec."Number of Threads" := 4;
        Rec.DeleteData := true;
#if ONPREM
        Rec."Import Use SQL Bulk" := true; // fastest OnPrem import
#endif

        // Decompress metadata
        if IsMetaGZ then begin
            Rec."Metadata Json Content".CreateInStream(InStr);
            TempBlob.CreateOutStream(OutStr);
            ZipMgt.GZipDecompress(InStr, OutStr);
            TempBlob.CreateInStream(InStr);
            Rec."Metadata Json Content".CreateOutStream(OutStr);
            CopyStream(OutStr, InStr); // copy decompressed json into record blob
        end;

        // Parse metadata
        ArchiveMgt.ParseJsonMetaData(Rec); // import all data related to files, tables and fields
        Rec.TestField("Archive ID"); // Must be imported from the json metadata
        if not Rec.Insert(true) then
            Rec.Modify(true);

        // Import table data files
        if GuiAllowed then
            Window.Open(ProgressLbl);

        ChunkData.SetRange("Archive ID", Rec."Archive ID");
        ChunkData.SetRange("Archive Seq. No.", Rec."Archive Sequence No.");
        ChunkData.SetRange("Archive Name", Rec."Archive Name");
        if not ChunkData.FindSet() then // Shall be loaded from the json, above in ParseJsonMetaData()
            Error('There is no files defined in the archive metadata.');
        FileNo := 1;
        repeat
            ChunkData.Data.CreateOutStream(OutStr);
            if (ChunkData."File Name" = '') or (ChunkData."Compressed Length" <= 0) or (ChunkData."Uncompressed Length" <= 0) then
                Error('Archive metadata corrupted, missing file informations.');
            if IsTar then
                TarArchiveMgt.ExtractEntry(ChunkData."File Name", OutStr)
            else
                ZipMgt.ExtractEntry(ChunkData."File Name", OutStr);
            ChunkData.Modify();

            if GuiAllowed then begin
                Window.Update(1, ProgressBar(FileNo / Rec."No. Files"));
                Window.Update(2, Format(FileNo) + ' / ' + format(Rec."No. Files"));
            end;
            FileNo += 1;
        until ChunkData.Next() = 0;
        clear(TarArchiveMgt);

        if GuiAllowed then
            Window.CLose();
        exit(true);
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
    #endregion

    procedure DownloadArchiveFile()
    var
        ArchMgt: Codeunit "TOO Pipou Archive Meta Mgt.";
        TarInStream: InStream;
        TempBlob: Codeunit "Temp Blob";
        FileName: Text;
    begin
        // Create metadata and TAR archive
        ArchMgt.CreateArchiveFile(Rec, TempBlob);
        TempBlob.CreateInStream(TarInStream);

        // Download file on client
        FileName := Rec."Archive Name";
        DownloadFromStream(TarInStream, '', '', '', FileName);
    end;
}