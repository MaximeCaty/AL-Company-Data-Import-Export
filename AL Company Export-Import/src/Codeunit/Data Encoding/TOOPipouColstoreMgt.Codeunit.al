codeunit 51013 "TOO Pipou colstore Mgt."
{
    #region Read
    procedure OpenColStore(ArchiveFile: Record "TOO Pipou Archive Files")
    var
        ColStoreFileInStr: InStream;
        DecompressedBlob: Codeunit "Temp Blob";
        DecompressedOutStr: OutStream;
        DecompressedInStr: InStream;
        TarEntries: List of [Text];
        MetadataBlob: Codeunit "Temp Blob";
        MetadataOutStr: OutStream;
        MetadataInStr: InStream;
        I: Integer;
        ColumnCompressedBlob: Codeunit "Temp Blob";
        ColumnOutStr: OutStream;
        ColumnInStr: InStream;
        CalulatedHash: Text;
        Hash: Codeunit "Cryptography Management";
        HashAlgorithmType: Option MD5,SHA1,SHA256,SHA384,SHA512;
        MetaDataFile: Text;
    begin
        ArchiveFile.TestField("Column Storage");
        ArchiveFile.data.CreateInStream(ColStoreFileInStr);
        if (ArchiveFile."Compression Mode" in [ArchiveFile."Compression Mode"::None]) then
            // NO COMPRESSION
            TarMgt.OpenTarArchive(ColStoreFileInStr)
        else begin
            // WHOLE FILE COMPRESSION
            DecompressedBlob.CreateOutStream(DecompressedOutStr);
            AdvCompress.Decompress(ColStoreFileInStr, DecompressedOutStr, ArchiveFile."Compression Mode");
            DecompressedInStr := DecompressedBlob.CreateInStream();
            // Decompression Signature integrity check
            if ArchiveFile."Uncompressed MD5 Hash" <> '' then begin
                CalulatedHash := Hash.GenerateHash(DecompressedInStr, HashAlgorithmType::MD5);
                if ArchiveFile."Uncompressed MD5 Hash" <> CalulatedHash then
                    Error('File "%1" decompression integrity check failed.\Original data signature hash : %2\Decompressed data signature hash : %3', ArchiveFile."File Name", ArchiveFile."Uncompressed MD5 Hash", CalulatedHash);
                DecompressedInStr.ResetPosition();
            end;
            TarMgt.OpenTarArchive(DecompressedInStr);
        end;

        // Get Metadata file
        TarMgt.GetEntryList(TarEntries);
        if TarEntries.Contains(ColStoreMetaDataFile) then
            MetaDataFile := ColStoreMetaDataFile
        else
            // other file name for legacy support
            if TarEntries.Contains('.json') then
                MetaDataFile := '.json'
            else
                if TarEntries.Contains('metadata.json') then
                    MetaDataFile := 'metadata.json'
                else
                    Error('Colstore file "%1" : Missing column metadata json file.', ArchiveFile."File Name");
        MetadataOutStr := MetadataBlob.CreateOutStream();
        TarMgt.ExtractEntry(MetaDataFile, MetadataOutStr);
        MetadataInStr := MetadataBlob.CreateInStream();

        // Parse metadata
        ParseColumnsFromInStream(MetadataInStr);

        // Load each Columns
        for I := 1 to ColCount do begin
            if not TarEntries.Contains(ColumnFileName[I]) then
                Error('Colstore file "%1" : column data file "%2" is missing in colstore.', ArchiveFile."File Name", ColumnFileName[I]);

            // EXTRACT COLUMN STREAM
            ColumnOutStr := ColumnBlobArr[I].CreateOutStream();
            TarMgt.ExtractEntry(ColumnFileName[I], ColumnOutStr);
            ColumnInStrArr[I] := ColumnBlobArr[I].CreateInStream();

            if ColumnInStrArr[I].Length = 0 then
                Error('Colstore file "%1" : extracted column data "%2" is empty.', ArchiveFile."File Name", ColumnFileName[I]);
        end;
    end;

    procedure GetColumnInStr(ColumnIndex: Integer; var InStr: InStream)
    begin
        InStr := ColumnInStrArr[ColumnIndex];
    end;

    procedure GetOriginalfieldIDColumnInStr(OriginalFieldID: Integer; var InStr: InStream)
    var
        i: Integer;
    begin
        for i := 1 to ColCount do
            if ColumnOriginalFieldID[i] = OriginalFieldID then begin
                InStr := ColumnInStrArr[i];
                exit;
            end;
        Error('The original Field %1 column were not found in the colstore file.', OriginalFieldID);
    end;

    procedure CoumnCount(): Integer
    begin
        exit(ColCount);
    end;
    #endregion

    #region Read Col Meta
    local procedure ParseColumnsFromInStream(JsonInStream: InStream)
    var
        RootObject: JsonObject;
        ColumnsToken: JsonToken;
        ColumnsArray: JsonArray;
        ColumnToken: JsonToken;
        ColumnObject: JsonObject;
        i: Integer;
        CompressionText: Text;
    begin
        // Clear previous data
        Clear(ColumnOriginalFieldID);
        Clear(ColumnFileName);
        ColCount := 0;

        // Read the root JSON object from the InStream
        if not RootObject.ReadFrom(JsonInStream) then
            Error('Invalid JSON format or unable to read from stream.');

        // Get the "count" value
        if RootObject.Get('count', ColumnsToken) then
            ColCount := ColumnsToken.AsValue().AsInteger()
        else
            Error('Missing "count" in JSON.');

        // Get the "columns" array
        if not RootObject.Get('columns', ColumnsToken) then
            Error('Missing "columns" array in JSON.');
        ColumnsArray := ColumnsToken.AsArray();

        // Validate count matches array length (optional)
        if ColumnsArray.Count() <> ColCount then
            Error('Count does not match the number of columns in the array.');

        // Iterate over each column object in the array
        for i := 0 to ColumnsArray.Count() - 1 do begin
            ColumnsArray.Get(i, ColumnToken);
            ColumnObject := ColumnToken.AsObject();

            // Field ID
            if ColumnObject.Get('Field ID', ColumnToken) then
                ColumnOriginalFieldID[i + 1] := ColumnToken.AsValue().AsInteger()
            else
                Error('Missing "Field ID" in column %1.', i + 1);

            // File Name
            if ColumnObject.Get('Column File Name', ColumnToken) then
                ColumnFileName[i + 1] := CopyStr(ColumnToken.AsValue().AsText(), 1, MaxStrLen(ColumnFileName[i + 1]))
            else
                Error('Missing "Column File Name" in column %1.', i + 1);
        end;
    end;
    #endregion

    #region Write
    procedure CreateColStore()
    begin
        TarMgt.CreateTarArchive();
        MetaWritten := false;
        ColCount := 0;
    end;

    procedure AddColumn(Archive: Record "TOO Pipou Archive"; var ArchiveFile: Record "TOO Pipou Archive Files"; var Tablefields: Record "TOO Pipou Archive Fields"; var ColumnBlob: codeunit "Temp Blob")
    var
        InStr: InStream;
    begin
        // Check blob content
        if ColumnBlob.Length() = 0 then
            Error('Error while exporting table %1 : binary stream for field %2 %3 is empty.', ArchiveFile."Table Name", Tablefields."Table ID", Tablefields."Field Name");

        ColCount += 1;
        ColumnFileName[ColCount] := Tablefields."Field Name".Replace(' ', '_').Replace('.', '_');
        ColumnOriginalFieldID[ColCount] := Tablefields."Field ID";

        // Append column data to the tar without compression
        ColumnBlob.CreateInStream(InStr);
        TarMgt.WriteTarEntry(InStr, ColumnFileName[ColCount]);

        // Free ram column we append to the file
        Clear(ColumnBlob);
    end;

    procedure ReadColStore(var InStream: InStream)
    begin
        WriteColumnMetadata();
        TarMgt.SaveTarArchive(InStream);
    end;

    procedure WriteColstoreTo(var OutStream: OutStream)
    begin
        WriteColumnMetadata();
        TarMgt.SaveTarArchive(OutStream);
    end;
    #endregion


    #region CompressCol
    local procedure CompressColumn(var Archive: Record "TOO Pipou Archive"; var TempBlobToCompress: Codeunit "Temp Blob"; var CopyToOutStream: OutStream) CompressionUsed: Enum "TOO Compression Algo."
    var
        InStr: InStream;
        PipouExportMgt: Codeunit "TOO Pipou Export Data";
    begin
        // Compress
        TempBlobToCompress.CreateInStream(InStr);
        CompressionUsed := PipouExportMgt.DetectBestCompression(Archive, InStr);
        AdvCompress.Compress(InStr, CopyToOutStream, CompressionUsed);
    end;
    #endregion

    #region Write Col Meta
    local procedure WriteColumnMetadata()
    var
        SerializedJson: Text;
        MetaJson: JsonObject;
        ColumnsArray: JsonArray;
        ColumnJson: JsonObject;
        I: Integer;
    begin
        // Create the JSON structure:
        // {
        //   "count": 10,
        //   "columns": [
        //     { "Field ID": 1, 
        //       "File Name": "field_1.gz", 
        //       "File Compression": "Gzip" 
        //     },
        //     ...
        //   ]
        // }
        if MetaWritten then exit;
        MetaJson.Add('count', ColCount);
        Clear(ColumnsArray);
        for I := 1 to ColCount do begin
            Clear(ColumnJson);
            ColumnJson.Add('Field ID', ColumnOriginalFieldID[I]);
            ColumnJson.Add('Column File Name', ColumnFileName[I]);
            ColumnsArray.Add(ColumnJson);
        end;
        MetaJson.Add('columns', ColumnsArray);

        // Write the JSON directly to the OutStream
        MetaJson.WriteTo(SerializedJson);
        TarMgt.WriteTarEntry(SerializedJson, ColStoreMetaDataFile);
        MetaWritten := true;
    end;
    #endregion


    var
        MetaWritten: Boolean;
        AdvCompress: Codeunit "TOO Advanced Compression Mgt.";
        TarMgt: Codeunit "TOO TAR Mgt.";
        ColCount: Integer;
        ColumnOriginalFieldID: Array[1024] of Integer;
        ColumnFileName: Array[1024] of Text[150];
        ColumnBlobArr: array[1024] of Codeunit "Temp Blob";
        ColumnInStrArr: array[1024] of InStream;
        ColStoreMetaDataFile: Label 'columns.json';
}