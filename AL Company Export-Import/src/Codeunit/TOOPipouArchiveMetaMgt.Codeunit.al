codeunit 51012 "TOO Pipou Archive Meta Mgt."
{
    #region Create Archive
    procedure CreateArchiveFile(Archive: Record "TOO Pipou Archive"; var TarTempBlob: Codeunit "Temp Blob")
    var
        ArchiveDict: Record "TOO Pipou Archive Dict.";
        ArchiveFields: Record "TOO Pipou Archive Fields";
        ArchiveFile: Record "TOO Pipou Archive Files";
        ArchiveTables: Record "TOO Pipou Archive Tables";
        TarMgt: Codeunit "TOO TAR Mgt.";
        TempBlobMeta, TempBlobMetaGZ : Codeunit "Temp Blob";
        Mgt: Codeunit "TOO Pipou Mgt.";
        DataComp: Codeunit "Data Compression";
        Window: Dialog;
        InStr: InStream;
        ChunkCount: Integer;
        I: Integer;
        JsonDictArray: JsonArray;
        JsonDictObj: JsonObject;
        JsonFileObj: JsonObject;
        CreatingArchive: Label 'Merging files into an archive... \ #1########### \ #2#########';
        ChunkOutStr: OutStream;
        LF: Text[1];
    begin
        LF[1] := 10; // Line feed, '\n'

        TarMgt.CreateTarArchive();

        // Initialise metadata archive info.
        Clear(JsonArchive);
        Clear(JsonTableArray);
        Clear(JsonFilesArray);
        Clear(JsonFieldArray);
        JsonAddArchiveInfo(Archive);

        if GuiAllowed then
            Window.Open(CreatingArchive);

        // Write all sub file archive
        ArchiveFile.SetAutoCalcFields(Data);
        ArchiveFile.SetRange("Archive ID", Archive."Archive ID");
        ArchiveFile.SetRange("Archive Name", Archive."Archive Name");
        ChunkCount := ArchiveFile.Count();
        if ArchiveFile.FindSet() then
            repeat
                // Write the file in archive
                ArchiveFile.Data.CreateInStream(InStr);
                if InStr.Length() = 0 then
                    Error('File %1 content is empty.', ArchiveFile."File Name");
                TarMgt.WriteTarEntry(InStr, ArchiveFile."File Name");

                // File Metadata
                JsonFileObj.Add('File Name', ArchiveFile."File Name");
                JsonFileObj.Add('Table ID', ArchiveFile."Table ID");
                JsonFileObj.Add('Table Name', ArchiveFile."Table Name");
                JsonFileObj.Add('Compression Mode', Format(ArchiveFile."Compression Mode"));
                JsonFileObj.Add('Compressed Length', ArchiveFile."Compressed Length");
                JsonFileObj.Add('Uncompressed Length', ArchiveFile."Uncompressed Length");
                JsonFileObj.Add('Start Index', ArchiveFile."Start Index");
                JsonFileObj.Add('End Index', ArchiveFile."End Index");
                JsonFileObj.Add('Chunk No.', ArchiveFile."Chunk No.");
                if ArchiveFile."Column Storage" then
                    JsonFileObj.Add('Transposed', ArchiveFile."Column Storage");
                if ArchiveFile."Uncompressed MD5 Hash" <> '' then
                    JsonFileObj.Add('MD5 Hash', ArchiveFile."Uncompressed MD5 Hash");
                JsonFileObj.Add('Export Date Time', Archive."Exported Date Time");
                JsonFilesArray.Add(JsonFileObj);
                Clear(JsonFileObj);

                I += 1;

                if GuiAllowed then begin
                    Window.Update(1, Mgt.ProgressBar(I / ChunkCount));
                    Window.Update(2, Format(I) + ' / ' + Format(ChunkCount));
                end;
            until ArchiveFile.Next() = 0;

        // Write the FK dictionaries at archive root, ahead of the table members. A dictionary no column ever looked
        // a value up in is skipped : blob and metadata entry disappear together, so the import never expects it.
        ArchiveDict.SetAutoCalcFields(Data);
        ArchiveDict.SetRange("Archive ID", Archive."Archive ID");
        ArchiveDict.SetRange(Used, true);
        if ArchiveDict.FindSet() then
            repeat
                ArchiveDict.Data.CreateInStream(InStr);
                TarMgt.WriteTarEntry(InStr, ArchiveDict.ArchiveEntryName());
                JsonDictObj.Add('File Name', ArchiveDict."File Name");
                JsonDictObj.Add('Table No.', ArchiveDict."Table No.");
                JsonDictObj.Add('Entry Count', ArchiveDict."Entry Count");
                JsonDictArray.Add(JsonDictObj);
                Clear(JsonDictObj);
            until ArchiveDict.Next() = 0;
        JsonArchive.Add('Dictionaries', JsonDictArray);

        // Write exported tables and fields definition
        ArchiveTables.SetRange("Archive ID", Archive."Archive ID");
        ArchiveTables.FindSet();
        repeat
            JsonAddTableInfo(ArchiveTables);
            ArchiveFields.SetRange("Archive ID", Archive."Archive ID");
            ArchiveFields.SetRange("Table ID", ArchiveTables."Table ID");
            ArchiveFields.FindSet();
            repeat
                JsonAddFieldInfo(ArchiveFields);
            until ArchiveFields.Next() = 0;
            JsonStoreTable();
        until ArchiveTables.Next() = 0;

        // Write files metadata
        Clear(TempBlobMeta);
        JsonArchive.Add('Tables', JsonTableArray);
        JsonArchive.Add('Files', JsonFilesArray);
        TempBlobMeta.CreateOutStream(ChunkOutStr);
        JsonArchive.WriteTo(ChunkOutStr);
        TempBlobMeta.CreateInStream(InStr);
        // Compress Meta with gzip (can easly be 2 MB +)
        TempBlobMetaGZ.CreateOutStream(ChunkOutStr);
        DataComp.GZipCompress(InStr, ChunkOutStr);
        TempBlobMetaGZ.CreateInStream(InStr);
        TarMgt.WriteTarEntry(InStr, 'datameta.json.gz');

        if GuiAllowed then
            Window.Close();

        // Create the Tar
        TarMgt.SaveTarArchive(TarTempBlob);
    end;
    #endregion

    #region Write Meta
    var
        JsonFieldArray: JsonArray;
        JsonFilesArray: JsonArray;
        JsonTableArray: JsonArray;
        JsonArchive: JsonObject;
        JsonFieldInfo: JsonObject;
        JsonTableInfo: JsonObject;


    procedure JsonAddArchiveInfo(Archive: Record "TOO Pipou Archive")
    var
        PipouMgt: Codeunit "TOO Pipou Mgt.";
    begin
        // Write global archive info.
        JsonArchive.Add('ID', Archive."Archive ID");
        JsonArchive.Add('Sequence No.', Archive."Archive Sequence No.");
        JsonArchive.Add('Version', PipouMgt.ArchiveFormatVersion()); // see ArchiveFormatVersion for what each version changes
        JsonArchive.Add('Export From CompanyName', Archive."Exported From Company");
        JsonArchive.Add('Export DateTime', Archive."Exported Date Time");
        JsonArchive.Add('Data Size (KB)', Archive."Files Size (KB)");
        JsonArchive.Add('Data Compressed Size (KB)', Archive."Files Compressed Size (KB)");
        JsonArchive.Add('Total Tables', Archive."Total Tables");
        JsonArchive.Add('No. Chunks', Archive."No. Files");
        JsonArchive.Add('Total Records', Archive."Total Records");
        JsonArchive.Add('Prefered Compression Mode', Archive."Prefered Compression Mode");
        JsonArchive.Add('Compression Level', Format(Archive."Compression Level")); // informative only, the level is not needed to decompress
        JsonArchive.Add('Enable Columns Transcoding', Archive."Enable Columns Transcoding");
    end;

    procedure JsonAddTableInfo(ArchiveTable: Record "TOO Pipou Archive Tables")
    begin
        Clear(JsonTableInfo);
        Clear(JsonFieldInfo);
        Clear(JsonFieldArray);
        JsonTableInfo.Add('ID', ArchiveTable."Table ID");
        JsonTableInfo.Add('Name', ArchiveTable."Table Name");
        JsonTableInfo.Add('Caption', ArchiveTable."Table Caption");
        JsonTableInfo.Add('DataPerCompany', ArchiveTable.DataPerCompany);
        JsonTableInfo.Add('From No. of Records', ArchiveTable."No. of Records");
    end;

    procedure JsonAddFieldInfo(var ArchiveTableField: Record "TOO Pipou Archive Fields")
    var
        EmptyInLst: List of [Text];
        InVal: Text;
    begin
        JsonFieldInfo.Add('No.', ArchiveTableField."Field ID");
        JsonFieldInfo.Add('FieldName', ArchiveTableField."Field Name");
        JsonFieldInfo.Add('Field Caption', ArchiveTableField."Field Caption");
        JsonFieldInfo.Add('Type', ArchiveTableField."Field Type");
        JsonFieldInfo.Add('Type Name', ArchiveTableField."Field Type Name");
        JsonFieldInfo.Add('Len', ArchiveTableField."Max Length");

        // FK dictionary encoding of that column
        if ArchiveTableField."Use Dictionary" then
            JsonFieldInfo.Add('Dict', ArchiveTableField."Dictionary File Name");

        // Save empty columns in chunk x or y :
        if ArchiveTableField."Empty In Chunks List" <> '' then begin
            EmptyInLst := Format(ArchiveTableField."Empty In Chunks List").Split(',');
            foreach InVal in EmptyInLst do
                JsonFieldInfo.Add('IsAllEmptyInChunk' + Format(InVal), true);
        end;
        JsonFieldArray.Add(JsonFieldInfo);
        Clear(JsonFieldInfo);
    end;

    procedure JsonStoreTable()
    begin
        JsonTableInfo.Add('Fields', JsonFieldArray);
        JsonTableArray.Add(JsonTableInfo);
        Clear(JsonTableInfo);
        Clear(JsonFieldArray);
        Clear(JsonFieldInfo);
    end;
    #endregion


    #region Import Meta
    procedure ParseJsonMetaData(var Archive: Record "TOO Pipou Archive")
    var
        JsonObj: JsonObject;
        TableMeta: Record "Table Metadata";
        ArchDict: Record "TOO Pipou Archive Dict.";
        ArchFields: Record "TOO Pipou Archive Fields";
        ArchFile: Record "TOO Pipou Archive Files";
        ArchTable: Record "TOO Pipou Archive Tables";
        AdvComp: Codeunit "TOO Advanced Compression Mgt.";
        Mgt: Codeunit "TOO Pipou Mgt.";
        Win: Dialog;
        InStr: InStream;
        AutoMatchedFields: Integer;
        I: Integer;
        DictArray: JsonArray;
        FieldsArray: JsonArray;
        FilesArray: JsonArray;
        TablesArray: JsonArray;
        DictObj: JsonObject;
        FieldObj: JsonObject;
        FileObj: JsonObject;
        TableObj: JsonObject;
        DictToken: JsonToken;
        FieldToken: JsonToken;
        FileToken: JsonToken;
        JsonToken: JsonToken;
        TableToken: JsonToken;
        ArchiveMeta: Label 'Archive global information';
        FilesMeta: Label 'Files metadata definitions';
        LoadingMeta: Label 'Loading archive data definition...\ #1####### \ #2######';
        TableMetaLbl: Label 'Tables metadata definitions';
        ErrUnsupportedCompression: Label 'The archive contain data with unsupported compression method (%1), you can not import the file with this version of the application.';
        ErrParseGuidLbl: Label 'Unable to parse the archive GUID : %1', Comment = '%1 = the raw GUID text found in the metadata';
    begin
        if GuiAllowed then begin
            Win.Open(LoadingMeta);
            Win.Update(1, ArchiveMeta);
        end;
        // Load json object
        Archive."Metadata Json Content".CreateInStream(InStr);
        JsonObj.ReadFrom(InStr);

        // Load archive infos
        // Tested : an unchecked SelectToken left the token uninitialized when the key was missing, and the
        // AsValue below then failed on a bare platform message instead of the archive error underneath.
        if not JsonObj.Get('ID', JsonToken) then
            Error('The archive metadata carries no "ID" key : the file is not a Pipou archive, or it is truncated.');
        Evaluate(Archive."Archive ID", JsonToken.AsValue().AsText());
        if IsNullGuid(Archive."Archive ID") then
            Error(ErrParseGuidLbl, JsonToken.AsValue().AsText());
        Archive."Archive Sequence No." := GetJsonIntAt(JsonObj, 'Sequence No.');
        Archive.Version := GetJsonIntAt(JsonObj, 'Version');
        if Archive.Version > 2 then
            Error('This application version used to export this archive (%1) is not supported. Please update the extension to use this archive.', Archive.Version);

        Archive."Prefered Compression Mode" := AdvComp.TextToEnum(GetJsonTextAt(JsonObj, 'Prefered Compression Mode'));
        Archive."Exported From Company" := GetJsonTextAt(JsonObj, 'Export From CompanyName');
        Archive."Exported Date Time" := GetJsonDTAt(JsonObj, 'Export DateTime');
        Archive."Files Size (KB)" := GetJsonDecAt(JsonObj, 'Data Size (KB)');
        Archive."Files Compressed Size (KB)" := GetJsonDecAt(JsonObj, 'Data Compressed Size (KB)');
        Archive."Total Tables" := GetJsonDecAt(JsonObj, 'Total Tables');
        Archive."No. Files" := GetJsonDecAt(JsonObj, 'No. Chunks');
        Archive."Total Records" := GetJsonDecAt(JsonObj, 'Total Records');
        Archive."Enable Columns Transcoding" := GetJsonBoolAt(JsonObj, 'Enable Columns Transcoding');
        if Archive."Files Size (KB)" <> 0 then
            Archive."Compression Ratio (%)" := Round(100 * (1 - (Archive."Files Compressed Size (KB)" / Archive."Files Size (KB)")), 0.01); // Percent

        // Files loop
        if GuiAllowed then
            Win.Update(1, FilesMeta);
        if JsonObj.Get('Files', FileToken) then begin  // Use Get for efficiency
            FilesArray := FileToken.AsArray();
            foreach FileToken in FilesArray do begin
                FileObj := FileToken.AsObject();
                ArchFile.Init();
                ArchFile."Archive ID" := Archive."Archive ID";
                ArchFile."Archive Name" := Archive."Archive Name";
                ArchFile."Archive Seq. No." := Archive."Archive Sequence No.";
                ArchFile."File Name" := GetJsonTextAt(FileObj, 'File Name');
                ArchFile."Table ID" := GetJsonIntAt(FileObj, 'Table ID');
                ArchFile."Table Name" := GetJsonTextAt(FileObj, 'Table Name');
                ArchFile."Uncompressed MD5 Hash" := GetJsonTextAt(FileObj, 'MD5 Hash');
                ArchFile."Chunk No." := GetJsonIntAt(FileObj, 'Chunk No.');
                // Column definition if transposed
                ArchFile."Column Storage" := GetJsonBoolAt(FileObj, 'Transposed');

                case GetJsonTextAt(FileObj, 'Compression Mode').Trim().ToLower() of
                    '1', 'gzip', 'gz':
                        ArchFile."Compression Mode" := ArchFile."Compression Mode"::Gzip;
                    '3', 'zstandard', 'zst':
                        ArchFile."Compression Mode" := ArchFile."Compression Mode"::zStandard;
                    '4', 'libbsc', 'bsc':
                        ArchFile."Compression Mode" := ArchFile."Compression Mode"::libbsc;
                    '7', 'kanzi', 'knz':
                        ArchFile."Compression Mode" := ArchFile."Compression Mode"::kanzi;
                end;
#if not ONPREM
                if not (ArchFile."Compression Mode" in [ArchFile."Compression Mode"::Gzip, ArchFile."Compression Mode"::None, ArchFile."Compression Mode"::"Auto (Cloud)"]) then
                    Error(ErrUnsupportedCompression, ArchFile."Compression Mode");
#endif

                ArchFile."Compressed Length" := GetJsonIntAt(FileObj, 'Compressed Length');
                ArchFile."Uncompressed Length" := GetJsonIntAt(FileObj, 'Uncompressed Length');
                if ArchFile."Uncompressed Length" > 0 then
                    ArchFile."Comp. Ratio" := Round(100 * (1 - (ArchFile."Compressed Length" / ArchFile."Uncompressed Length")), 0.01);
                ArchFile."Start Index" := GetJsonIntAt(FileObj, 'Start Index');
                ArchFile."End Index" := GetJsonIntAt(FileObj, 'End Index');
                ArchFile."Number Of Recs" := ArchFile."End Index" - ArchFile."Start Index";
                ArchFile.Insert();
                I += 1;
                if GuiAllowed then
                    Win.Update(2, Mgt.ProgressBar(I / FilesArray.Count()));
            end;
        end;
        Clear(FilesArray);
        Clear(FileObj);

        // FK dictionaries : the blob itself is extracted from the archive by ImportArchiveFile
        ArchDict.SetRange("Archive ID", Archive."Archive ID");
        ArchDict.DeleteAll();
        if JsonObj.Get('Dictionaries', DictToken) then begin
            DictArray := DictToken.AsArray();
            foreach DictToken in DictArray do begin
                DictObj := DictToken.AsObject();
                ArchDict.Init();
                ArchDict."Archive ID" := Archive."Archive ID";
                ArchDict."File Name" := CopyStr(GetJsonTextAt(DictObj, 'File Name'), 1, MaxStrLen(ArchDict."File Name"));
                ArchDict."Table No." := GetJsonIntAt(DictObj, 'Table No.');
                ArchDict."Entry Count" := GetJsonIntAt(DictObj, 'Entry Count');
                ArchDict.Insert();
            end;
        end;
        Clear(DictArray);
        Clear(DictObj);

        // Tables loop - Optimized
        if GuiAllowed then
            Win.Update(1, TableMetaLbl);
        I := 0;
        if JsonObj.Get('Tables', TableToken) then begin
            TablesArray := TableToken.AsArray();
            foreach TableToken in TablesArray do begin
                TableObj := TableToken.AsObject();
                ArchTable.Init();
                ArchTable."Archive ID" := Archive."Archive ID";
                ArchTable."Table ID" := GetJsonIntAt(TableObj, 'ID');
                ArchTable."Table Name" := GetJsonTextAt(TableObj, 'Name');
                ArchTable."Table Caption" := GetJsonTextAt(TableObj, 'Caption');
                ArchTable."No. of Records" := GetJsonIntAt(TableObj, 'From No. of Records');
                ArchTable.DataPerCompany := GetJsonBoolAt(TableObj, 'DataPerCompany');
                // Try to match table
                TableMeta.SetRange(ID, ArchTable."Table ID");
                if TableMeta.FindFirst() then begin
                    ArchTable."Matched Table ID" := ArchTable."Table ID";
                    ArchTable."Select For Import" := true;
                end;

                // Fields sub-loop
                AutoMatchedFields := 0;
                if TableObj.Get('Fields', FieldToken) then begin
                    FieldsArray := FieldToken.AsArray();
                    foreach FieldToken in FieldsArray do begin
                        FieldObj := FieldToken.AsObject();
                        ArchFields.Init();
                        ArchFields."Archive ID" := Archive."Archive ID";
                        ArchFields."Table ID" := ArchTable."Table ID";
                        ArchFields."Field ID" := GetJsonIntAt(FieldObj, 'No.');
                        ArchFields."Field Name" := GetJsonTextAt(FieldObj, 'FieldName');
                        ArchFields."Field Caption" := GetJsonTextAt(FieldObj, 'Field Caption');
                        Evaluate(ArchFields."Field Type", GetJsonTextAt(FieldObj, 'Type'));
                        ArchFields."Max Length" := GetJsonIntAt(FieldObj, 'Len');
                        // Empty columns detection - To be improved
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk1') then
                            ArchFields."Empty In Chunks List" += '1,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk2') then
                            ArchFields."Empty In Chunks List" += '2,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk3') then
                            ArchFields."Empty In Chunks List" += '3,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk4') then
                            ArchFields."Empty In Chunks List" += '4,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk5') then
                            ArchFields."Empty In Chunks List" += '5,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk6') then
                            ArchFields."Empty In Chunks List" += '6,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk7') then
                            ArchFields."Empty In Chunks List" += '7,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk8') then
                            ArchFields."Empty In Chunks List" += '8,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk9') then
                            ArchFields."Empty In Chunks List" += '9,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk10') then
                            ArchFields."Empty In Chunks List" += '10,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk11') then
                            ArchFields."Empty In Chunks List" += '11,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk12') then
                            ArchFields."Empty In Chunks List" += '12,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk13') then
                            ArchFields."Empty In Chunks List" += '13,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk14') then
                            ArchFields."Empty In Chunks List" += '14,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk15') then
                            ArchFields."Empty In Chunks List" += '15,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk16') then
                            ArchFields."Empty In Chunks List" += '16,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk17') then
                            ArchFields."Empty In Chunks List" += '17,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk18') then
                            ArchFields."Empty In Chunks List" += '18,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk19') then
                            ArchFields."Empty In Chunks List" += '19,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk19') then
                            ArchFields."Empty In Chunks List" += '20,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk20') then
                            ArchFields."Empty In Chunks List" += '20,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk21') then
                            ArchFields."Empty In Chunks List" += '21,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk22') then
                            ArchFields."Empty In Chunks List" += '22,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk23') then
                            ArchFields."Empty In Chunks List" += '23,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk24') then
                            ArchFields."Empty In Chunks List" += '24,';
                        if GetJsonBoolAt(FieldObj, 'IsAllEmptyInChunk25') then
                            ArchFields."Empty In Chunks List" += '25,';
                        ArchFields."Empty In Chunks List" := ArchFields."Empty In Chunks List".TrimEnd(',');
                        // FK dictionary encoding : absent on archives written before this existed, so the literal path stays the default
                        ArchFields."Dictionary File Name" := CopyStr(GetJsonTextAt(FieldObj, 'Dict'), 1, MaxStrLen(ArchFields."Dictionary File Name"));
                        if ArchFields."Dictionary File Name" <> '' then
                            ArchFields."Use Dictionary" := true;

                        // Try to match field
                        ArchFields."Matched Table ID" := ArchTable."Table ID"; // avoid additional calcfield
                        ArchFields.SearchMatchingField(ArchTable."Table ID");
                        ArchFields.Insert();
                        if ArchFields."Matched Field ID" <> 0 then
                            AutoMatchedFields += 1;
                    end;
                end;

                // Table Match Status
                if (ArchTable."Matched Table ID" = 0) or (AutoMatchedFields = 0) then
                    ArchTable."Match Status" := ArchTable."Match Status"::Missing
                else
                    if AutoMatchedFields = FieldsArray.Count() then
                        ArchTable."Match Status" := ArchTable."Match Status"::Full
                    else
                        ArchTable."Match Status" := ArchTable."Match Status"::Partial;
                ArchTable.Insert();

                I += 1;
                if GuiAllowed then
                    Win.Update(2, Mgt.ProgressBar(I / TablesArray.Count()));
            end;
        end;
        if GuiAllowed then
            Win.Close();
    end;
    #endregion

    #region JSON Helper
    // Direct key lookup, not a JSONPath : SelectToken re-parses its path string on every call (tokenize, build a
    // filter chain, then walk it) where Get is a single hashtable hit on the key. The metadata reader calls these
    // ~30 times per field, so the parsing dominated the whole import of a large archive.
    // The key is taken literally too : "Chunk No.", "Data Size (KB)" and the like need no quoting or bracketing,
    // and the dots and spaces they carry are no longer parsed as path syntax.
    // Get only reaches the direct children of JsObj : every caller passes the object that owns the key.
    local procedure GetJsonTextAt(var JsObj: JsonObject; KeyName: Text): Text
    var
        JsonTok: JsonToken;
    begin
        if not JsObj.Get(KeyName, JsonTok) then
            exit('');
        if not JsonTok.IsValue then
            Error('The token at key %1 is not a value.', KeyName);
        exit(JsonTok.AsValue().AsText());
    end;

    local procedure GetJsonIntAt(var JsObj: JsonObject; KeyName: Text): Integer
    var
        JsonTok: JsonToken;
    begin
        if not JsObj.Get(KeyName, JsonTok) then
            exit(0);
        if not JsonTok.IsValue then
            Error('The token at key %1 is not a value.', KeyName);
        exit(JsonTok.AsValue().AsInteger());
    end;

    local procedure GetJsonDecAt(var JsObj: JsonObject; KeyName: Text): Decimal
    var
        JsonTok: JsonToken;
    begin
        if not JsObj.Get(KeyName, JsonTok) then
            exit(0);
        if not JsonTok.IsValue then
            Error('The token at key %1 is not a value.', KeyName);
        exit(JsonTok.AsValue().AsDecimal());
    end;

    local procedure GetJsonDTAt(var JsObj: JsonObject; KeyName: Text): DateTime
    var
        JsonTok: JsonToken;
    begin
        if not JsObj.Get(KeyName, JsonTok) then
            exit(0DT);
        if not JsonTok.IsValue then
            Error('The token at key %1 is not a value.', KeyName);
        exit(JsonTok.AsValue().AsDateTime());
    end;

    local procedure GetJsonBoolAt(var JsObj: JsonObject; KeyName: Text): Boolean
    var
        JsonTok: JsonToken;
    begin
        if not JsObj.Get(KeyName, JsonTok) then
            exit(false);
        if not JsonTok.IsValue then
            Error('The token at key %1 is not a value.', KeyName);
        exit(JsonTok.AsValue().AsBoolean());
    end;
    #endregion
}