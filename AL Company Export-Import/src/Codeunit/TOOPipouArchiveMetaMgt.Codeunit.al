codeunit 51012 "TOO Pipou Archive Meta Mgt."
{
    #region Create Archive
    procedure CreateArchiveFile(Archive: Record "TOO Pipou Archive"; var TarTempBlob: codeunit "Temp Blob")
    var
        InStr: InStream;
        TarMgt: Codeunit "TOO TAR Mgt.";
        ZipMgt: Codeunit "Data Compression";
        ArchiveFile: Record "TOO Pipou Archive Files";
        CreatingArchive: Label 'Merging files into an archive... \ #1########### \ #2#########';
        I: Integer;
        ChunkCount: Integer;
        Window: Dialog;
        ImpExpMgt: codeunit "TOO Import/Export Mgt";
        TempBlobMeta: Codeunit "Temp Blob";
        TempBlobCompressedMeta: Codeunit "Temp Blob";
        ChunkOutStr: OutStream;
        LF: Text[1];
        JsonFileObj: JsonObject;
        ArchiveTables: Record "TOO Pipou Archive Tables";
        ArchiveFields: Record "TOO Pipou Archive Fields";
    begin
        LF[1] := 10; // Line feed, '\n'

        ZipMgt.CreateZipArchive();
        //TarMgt.CreateTarArchive();

        // Initialise metadata archive info.
        clear(JsonArchive);
        clear(JsonTableArray);
        clear(JsonFilesArray);
        clear(JsonFieldArray);
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
                ZipMgt.AddEntry(InStr, ArchiveFile."File Name");
                //TarMgt.WriteTarEntry(InStr, ArchiveFile."File Name");

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
                    Window.Update(1, ImpExpMgt.ProgressBar(I / ChunkCount));
                    Window.Update(2, Format(I) + ' / ' + Format(ChunkCount));
                end;
            until ArchiveFile.Next() = 0;

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
        clear(TempBlobMeta);
        JsonArchive.Add('Tables', JsonTableArray);
        JsonArchive.Add('Files', JsonFilesArray);
        TempBlobMeta.CreateOutStream(ChunkOutStr);
        JsonArchive.WriteTo(ChunkOutStr);
        TempBlobMeta.CreateInStream(InStr);
        /*if InStr.Length > 102400 then begin // meta larger than 100 KB 
            // Compressed metadata
            TempBlobCompressedMeta.CreateOutStream(ChunkOutStr);
            ZipMgt.GZipCompress(InStr, ChunkOutStr);
            TempBlobCompressedMeta.CreateInStream(InStr);
            TarMgt.WriteTarEntry(InStr, 'datameta.json.gz');
        end else*/
        ZipMgt.AddEntry(InStr, 'datameta.json');
        //TarMgt.WriteTarEntry(InStr, 'datameta.json');

        if GuiAllowed then
            Window.Close();

        // Write permissions set
        /*PipoutMgt.ExportTenantPermissionSetsGzip(TempBlobChunk);
        TempBlobChunk.CreateInStream(InStr);
        TarMgt.WriteTarEntry(InStr, 'UserDefinedPermissionSets.xml.gz');*/

        // Create the Tar
        ZipMgt.SaveZipArchive(TarTempBlob);
        //TarMgt.SaveTarArchive(TarTempBlob);
    end;
    #endregion

    #region Write Meta
    var
        JsonArchive: JsonObject;
        JsonTableArray: JsonArray;
        JsonFilesArray: JsonArray;
        JsonTableInfo: JsonObject;
        JsonFieldArray: JsonArray;
        JsonFieldInfo: JsonObject;


    procedure JsonAddArchiveInfo(Archive: Record "TOO Pipou Archive")
    begin
        // Write global archive info.
        JsonArchive.Add('ID', Archive."Archive ID");
        JsonArchive.Add('Sequence No.', Archive."Archive Sequence No.");
        JsonArchive.Add('Export From CompanyName', Archive."Exported From Company");
        JsonArchive.Add('Export DateTime', Archive."Exported Date Time");
        JsonArchive.Add('Data Size (KB)', Archive."Files Size (KB)");
        JsonArchive.Add('Data Compressed Size (KB)', Archive."Files Compressed Size (KB)");
        JsonArchive.Add('Total Tables', Archive."Total Tables");
        JsonArchive.Add('No. Chunks', Archive."No. Files");
        JsonArchive.Add('Total Records', Archive."Total Records");
        JsonArchive.Add('Prefered Compression Mode', Archive."Prefered Compression Mode");
        JsonArchive.Add('Enable Optimal Encode', Archive."Enable Optimal Encode");
        JsonArchive.Add('Enable Columns Transcoding', Archive."Enable Columns Transcoding");
        if Archive."Diff. Export Start DT" <> 0DT then begin
            JsonArchive.Add('Is Differential Export', true);
            JsonArchive.Add('Differential Export From DT', Archive."Diff. Export Start DT");
        end else
            JsonArchive.Add('Is Differential Export', false);
    end;

    procedure JsonAddTableInfo(ArchiveTable: Record "TOO Pipou Archive Tables")
    begin
        Clear(JsonTableInfo);
        clear(JsonFieldInfo);
        Clear(JsonFieldArray);
        JsonTableInfo.Add('ID', ArchiveTable."Table ID");
        JsonTableInfo.Add('Name', ArchiveTable."Table Name");
        JsonTableInfo.Add('Caption', ArchiveTable."Table Caption");
        JsonTableInfo.Add('DataPerCompany', ArchiveTable.DataPerCompany);
        JsonTableInfo.Add('From No. of Records', ArchiveTable."No. of Records");
        JsonTableInfo.Add('From Record Size', ArchiveTable."Record Size");
        JsonTableInfo.Add('From Size (KB)', ArchiveTable."Original SQL Data+Index (KB)");
        JsonTableInfo.Add('From Data Size (KB)', ArchiveTable."Original Data Size (KB)");
        JsonTableInfo.Add('From Index Size (KB)', ArchiveTable."Original Index Size (KB)");
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

        // Save empty columns in chunk x or y :
        if ArchiveTableField."Empty In Chunks List" <> '' then begin
            EmptyInLst := Format(ArchiveTableField."Empty In Chunks List").Split(',');
            foreach InVal in EmptyInLst do
                JsonFieldInfo.Add('IsAllEmptyInChunk' + format(InVal), true);
        end;
        JsonFieldArray.Add(JsonFieldInfo);
        Clear(JsonFieldInfo);
    end;

    procedure JsonStoreTable();
    begin
        JsonTableInfo.Add('Fields', JsonFieldArray);
        JsonTableArray.Add(JsonTableInfo);
        clear(JsonTableInfo);
        clear(JsonFieldArray);
        clear(JsonFieldInfo);
    end;
    #endregion


    #region Import Meta
    var
        JsonObj: JsonObject;

    procedure ParseJsonMetaData(var Archive: Record "TOO Pipou Archive")
    var
        JsonToken: JsonToken;
        FilesArray: JsonArray;
        FileObj: JsonObject;
        FileToken: JsonToken;
        TableToken: JsonToken;
        TablesArray: JsonArray;
        TableObj: JsonObject;
        FieldObj: JsonObject;
        FieldsArray: JsonArray;
        FieldToken: JsonToken;
        InStr: InStream;
        ArchTable: Record "TOO Pipou Archive Tables";
        ArchFields: Record "TOO Pipou Archive Fields";
        ArchFile: Record "TOO Pipou Archive Files";
        Win: dialog;
        LoadingMeta: Label 'Loading archive data definition...\ #1####### \ #2######';
        ArchiveMeta: Label 'Archive global information';
        TableMetaLbl: Label 'Tables metadata definitions';
        FilesMeta: Label 'Files metadata definitions';
        Mgt: codeunit "TOO Pipou Mgt.";
        AdvComp: Codeunit "TOO Advanced Compression Mgt.";
        TableMeta: Record "Table Metadata";
        I: Integer;
    begin
        if GuiAllowed then begin
            Win.Open(LoadingMeta);
            Win.Update(1, ArchiveMeta);
        end;
        // Load json object
        Archive."Metadata Json Content".CreateInStream(InStr);
        JsonObj.ReadFrom(InStr);

        // Load archive infos
        JsonObj.SelectToken('$.ID', JsonToken);
        Evaluate(Archive."Archive ID", JsonToken.AsValue().AsText());
        if IsNullGuid(Archive."Archive ID") then
            Error('Unable to parse the archive GUID : ' + JsonToken.AsValue().AsText());
        Archive."Archive Sequence No." := GetJsonIntAt('$.[''Sequence No.'']');
        Archive."Prefered Compression Mode" := AdvComp.TextToEnum(GetJsonTextAt('$.[''Prefered Compression Mode'']'));
        Archive."Exported From Company" := GetJsonTextAt('$.[''Export From CompanyName'']');
        Archive."Exported Date Time" := GetJsonDTAt('$.[''Export DateTime'']');
        Archive."Files Size (KB)" := GetJsonDecAt('$.[''Data Size (KB)'']');
        Archive."Files Compressed Size (KB)" := GetJsonDecAt('$.[''Data Compressed Size (KB)'']');
        Archive."Total Tables" := GetJsonDecAt('$.[''Total Tables'']');
        Archive."No. Files" := GetJsonDecAt('$.[''No. Chunks'']');
        Archive."Total Records" := GetJsonDecAt('$.[''Total Records'']');
        Archive."Enable Optimal Encode" := GetJsonBoolAt('$.[''Enable Optimal Encode'']');
        Archive."Enable Columns Transcoding" := GetJsonBoolAt('$.[''Enable Columns Transcoding'']');
        if JsonObj.SelectToken('$.[''Is Differential Export'']', JsonToken) then
            if JsonToken.AsValue().AsBoolean() then
                Archive."Diff. Export Start DT" := GetJsonDTAt('$.[''Differential Export From DT'']');
        if Archive."Files Size (KB)" <> 0 then
            Archive."Compression Ratio (%)" := round(100 * (1 - (Archive."Files Compressed Size (KB)" / Archive."Files Size (KB)")), 0.01); // Percent

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
                ArchFile."File Name" := GetJsonText(FileObj, 'File Name');
                ArchFile."Table ID" := GetJsonInt(FileObj, 'Table ID');
                ArchFile."Table Name" := GetJsonText(FileObj, 'Table Name');
                ArchFile."Uncompressed MD5 Hash" := GetJsonText(FileObj, 'MD5 Hash');
                ArchFile."Chunk No." := GetJsonInt(FileObj, 'Chunk No.');
                // Column definition if transposed
                ArchFile."Column Storage" := GetJsonBool(FileObj, 'Transposed');

                case GetJsonText(FileObj, 'Compression Mode').Trim().ToLower() of
                    '1', 'gzip', 'gz':
                        ArchFile."Compression Mode" := ArchFile."Compression Mode"::Gzip;
#if ONPREM
                    '3', 'zstandard', 'zst':
                        ArchFile."Compression Mode" := ArchFile."Compression Mode"::Zstandard;
                    '4', 'libbsc', 'bsc':
                        ArchFile."Compression Mode" := ArchFile."Compression Mode"::libbsc;
#endif
                end;
                ArchFile."Compressed Length" := GetJsonInt(FileObj, 'Compressed Length');
                ArchFile."Uncompressed Length" := GetJsonInt(FileObj, 'Uncompressed Length');
                ArchFile."Comp. Ratio" := round(100 * (1 - (ArchFile."Compressed Length" / ArchFile."Uncompressed Length")), 0.01);
                ArchFile."Start Index" := GetJsonInt(FileObj, 'Start Index');
                ArchFile."End Index" := GetJsonInt(FileObj, 'End Index');
                ArchFile."Number Of Recs" := ArchFile."End Index" - ArchFile."Start Index";
                ArchFile.Insert();
                I += 1;
                if GuiAllowed then
                    Win.Update(2, Mgt.ProgressBar(I / FilesArray.Count()));
            end;
        end;
        clear(FilesArray);
        clear(FileObj);

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
                ArchTable."Table ID" := GetJsonInt(TableObj, 'ID');
                ArchTable."Table Name" := GetJsonText(TableObj, 'Name');
                ArchTable."Table Caption" := GetJsonText(TableObj, 'Caption');
                ArchTable."No. of Records" := GetJsonInt(TableObj, 'From No. of Records');
                ArchTable.DataPerCompany := GetJsonBool(TableObj, 'DataPerCompany');
                ArchTable."Record Size" := GetJsonDec(TableObj, 'From Record Size');
                ArchTable."Original SQL Data+Index (KB)" := GetJsonInt(TableObj, 'From Size (KB)');
                ArchTable."Original Data Size (KB)" := GetJsonInt(TableObj, 'From Data Size (KB)');
                ArchTable."Original Index Size (KB)" := GetJsonInt(TableObj, 'From Index Size (KB)');
                // Try to match table
                TableMeta.SetRange(ID, ArchTable."Table ID");
                if TableMeta.FindFirst() then begin
                    ArchTable."Matched Table ID" := ArchTable."Table ID";
                    ArchTable."Select For Import" := true;
                end;

                // Fields sub-loop
                if TableObj.Get('Fields', FieldToken) then begin
                    FieldsArray := FieldToken.AsArray();
                    foreach FieldToken in FieldsArray do begin
                        FieldObj := FieldToken.AsObject();
                        ArchFields.Init();
                        ArchFields."Archive ID" := Archive."Archive ID";
                        ArchFields."Table ID" := ArchTable."Table ID";
                        ArchFields."Field ID" := GetJsonInt(FieldObj, 'No.');
                        ArchFields."Field Name" := GetJsonText(FieldObj, 'FieldName');
                        ArchFields."Field Caption" := GetJsonText(FieldObj, 'Field Caption');
                        Evaluate(ArchFields."Field Type", GetJsonText(FieldObj, 'Type'));
                        ArchFields."Max Length" := GetJsonInt(FieldObj, 'Len');
                        // Empty columns detection - To be improved
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk1') then
                            ArchFields."Empty In Chunks List" += '1,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk2') then
                            ArchFields."Empty In Chunks List" += '2,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk3') then
                            ArchFields."Empty In Chunks List" += '3,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk4') then
                            ArchFields."Empty In Chunks List" += '4,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk5') then
                            ArchFields."Empty In Chunks List" += '5,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk6') then
                            ArchFields."Empty In Chunks List" += '6,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk7') then
                            ArchFields."Empty In Chunks List" += '7,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk8') then
                            ArchFields."Empty In Chunks List" += '8,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk9') then
                            ArchFields."Empty In Chunks List" += '9,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk10') then
                            ArchFields."Empty In Chunks List" += '10,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk11') then
                            ArchFields."Empty In Chunks List" += '11,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk12') then
                            ArchFields."Empty In Chunks List" += '12,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk13') then
                            ArchFields."Empty In Chunks List" += '13,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk14') then
                            ArchFields."Empty In Chunks List" += '14,';
                        if GetJsonBool(FieldObj, 'IsAllEmptyInChunk15') then
                            ArchFields."Empty In Chunks List" += '15,';
                        ArchFields."Empty In Chunks List" := ArchFields."Empty In Chunks List".TrimEnd(',');
                        // Try to match field
                        ArchFields."Matched Table ID" := ArchTable."Table ID"; // avoid additional calcfield                         
                        ArchFields.SearchMatchingField(ArchTable."Table ID");
                        ArchFields.Insert();
                    end;
                end;

                // Set Match Status
                ArchTable.UpdateMatchStatus();
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
    local procedure GetJsonTextAt(JsonPath: Text): Text
    var
        JsonTok: JsonToken;
    begin
        if not JsonObj.SelectToken(JsonPath, JsonTok) then
            exit('');
        if not JsonTok.IsValue then
            Error('The token at path %1 is not a value.', JsonPath);
        exit(JsonTok.AsValue().AsText());
    end;

    local procedure GetJsonIntAt(JsonPath: Text): Integer
    var
        JsonTok: JsonToken;
    begin
        if not JsonObj.SelectToken(JsonPath, JsonTok) then exit(0);
        if not JsonTok.IsValue then
            Error('The token at path %1 is not a value.', JsonPath);
        exit(JsonTok.AsValue().AsInteger());
    end;

    local procedure GetJsonDecAt(JsonPath: Text): Decimal
    var
        JsonTok: JsonToken;
    begin
        if not JsonObj.SelectToken(JsonPath, JsonTok) then exit(0);
        if not JsonTok.IsValue then
            Error('The token at path %1 is not a value.', JsonPath);
        exit(JsonTok.AsValue().AsDecimal());
    end;

    local procedure GetJsonDTAt(JsonPath: Text): DateTime
    var
        JsonTok: JsonToken;
    begin
        if not JsonObj.SelectToken(JsonPath, JsonTok) then exit(0DT);
        if not JsonTok.IsValue then
            Error('The token at path %1 is not a value.', JsonPath);
        exit(JsonTok.AsValue().AsDateTime());
    end;

    local procedure GetJsonBoolAt(JsonPath: Text): Boolean
    var
        JsonTok: JsonToken;
    begin
        if not JsonObj.SelectToken(JsonPath, JsonTok) then
            exit(false);
        if not JsonTok.IsValue then
            Error('The token at path %1 is not a value.', JsonPath);
        exit(JsonTok.AsValue().AsBoolean());
    end;

    local procedure GetJsonText(var JObj: JsonObject; JsonKey: Text): Text
    var
        JTok: JsonToken;
    begin
        if JObj.Get(JsonKey, JTok) then
            exit(JTok.AsValue().AsText());
        exit('');
    end;

    local procedure GetJsonInt(var JObj: JsonObject; JsonKey: Text): Integer
    var
        JTok: JsonToken;
    begin
        if JObj.Get(JsonKey, JTok) then
            exit(JTok.AsValue().AsInteger());
        exit(0);
    end;

    local procedure GetJsonDec(var JObj: JsonObject; JsonKey: Text): Decimal
    var
        JTok: JsonToken;
    begin
        if JObj.Get(JsonKey, JTok) then
            exit(JTok.AsValue().AsDecimal());
        exit(0);
    end;

    local procedure GetJsonDT(var JObj: JsonObject; JsonKey: Text): DateTime
    var
        JTok: JsonToken;
    begin
        if JObj.Get(JsonKey, JTok) then
            exit(JTok.AsValue().AsDateTime());
        exit(0DT);
    end;

    local procedure GetJsonBool(var JObj: JsonObject; JsonKey: Text): Boolean
    var
        JTok: JsonToken;
    begin
        if JObj.Get(JsonKey, JTok) then
            exit(JTok.AsValue().AsBoolean());
        exit(false);
    end;
    #endregion
}