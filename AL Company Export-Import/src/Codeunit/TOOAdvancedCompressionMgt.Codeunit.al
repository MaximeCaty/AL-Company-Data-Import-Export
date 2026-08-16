codeunit 51002 "TOO Advanced Compression Mgt."
{
    SingleInstance = true;


    procedure TextToEnum(CompressionModeText: Text) Compression: Enum "TOO Compression Algo."
    begin
        case CompressionModeText.ToLower().Trim() of
            '1', 'gzip', 'gz':
                Compression := Compression::Gzip;
            '3', 'zstandard', 'zst':
                Compression := Compression::zStandard;
            '4', 'libbsc', 'bsc':
                Compression := Compression::libbsc;
            '5', 'auto':
                Compression := Compression::"Auto (On-Premise)";
            '6', 'cloud':
                Compression := Compression::"Auto (Cloud)";
            '7', 'kanzi', 'knz':
                Compression := Compression::kanzi;
        end;
    end;
    #region Gen Comp/Dec
    procedure Compress(InputStream: InStream; OutputStream: OutStream; CompressMode: Enum "TOO Compression Algo.")
    var
        CompressLevel: Enum "TOO Compression Level";
    begin
        Compress(InputStream, OutputStream, CompressMode, CompressLevel::High);
    end;

    procedure Compress(InputStream: InStream; OutputStream: OutStream; CompressMode: Enum "TOO Compression Algo."; CompressLevel: Enum "TOO Compression Level")
    var
        CompressMgt: Codeunit "Data Compression";
    begin
        case CompressMode of

            CompressMode::None:
                CopyStream(OutputStream, InputStream);

            CompressMode::Gzip:
                CompressMgt.GZipCompress(InputStream, OutputStream);

#if ONPREM
            CompressMode::zStandard:
                ZstandardCompressStream(InputStream, OutputStream, ZstandardLevel(CompressLevel)); // Default level is 3 (1 - 22) : 3 = "very fast", 9 = "optimal", 19-22 = ultra

            CompressMode::libbsc:
                LibbscCompressStream(InputStream, OutputStream, LibbscArguments(CompressLevel));

            CompressMode::kanzi:
                KanziCompressStream(InputStream, OutputStream);
#endif
            else
                Error('Compression method "%1" is not supported', CompressMode);
        end
    end;

#if ONPREM
    /// <summary>
    /// zStandard compression level used for each compression level preset.
    /// </summary>
    procedure ZstandardLevel(CompressLevel: Enum "TOO Compression Level") Level: Integer
    begin
        case CompressLevel of
            CompressLevel::Medium:
                exit(12);
            CompressLevel::Extreme:
                exit(19);
            else
                exit(15); // High
        end;
    end;

    /// <summary>
    /// bsc.exe compression arguments used for each compression level preset (block size is added by the caller).
    /// </summary>
    procedure LibbscArguments(CompressLevel: Enum "TOO Compression Level") Arguments: Text
    begin
        case CompressLevel of
            CompressLevel::Medium:
                exit('-e2 -p');
            else
                exit('-e2 -r -s'); // High and Extreme (Extreme uses Kanzi when available, bsc is the fallback)
        end;
    end;
#endif

    procedure Decompress(InputStream: InStream; OutputStream: OutStream; CompressMode: Enum "TOO Compression Algo.")
    var
        CompressMgt: Codeunit "Data Compression";
    begin
        InputStream.ResetPosition();
        case CompressMode of

            CompressMode::None:
                CopyStream(OutputStream, InputStream);

            CompressMode::Gzip:
                CompressMgt.GZipDecompress(InputStream, OutputStream);

#if ONPREM
            CompressMode::zStandard:
                ZstandardDecompressStream(InputStream, OutputStream);

            CompressMode::libbsc:
                LibbscDecompressStream(InputStream, OutputStream);

            CompressMode::kanzi:
                KanziDecompressStream(InputStream, OutputStream);
#endif
            else
                Error('Compression method unsupported');
        end
    end;

    #endregion


    #region Libbsc
#if ONPREM
    procedure LibbscCompressStream(InStream: InStream; OutStream: OutStream; CompressionLevel: Integer) CompressedSize: Integer
    begin
        // Entropy coder level only (0, 1 or 2), 2 has the best ratio, 0 and 1 have no significant speed difference
        exit(LibbscCompressStream(InStream, OutStream, StrSubstNo('-e%1 -r', CompressionLevel)));
    end;

    procedure LibbscCompressStream(InStream: InStream; OutStream: OutStream; CompressionArguments: Text) CompressedSize: Integer
    var
        CompressedFile: File;
        FileOutStr: OutStream;
    begin
        InitBsc();

        // Save the stream to a temp file on the server
        if Erase(TempFileName) then;
        CompressedFile.WriteMode(true);
        if not CompressedFile.Create(TempFileName) then
            Error('Unable to create file %1', TempFileName);
        CompressedFile.CreateOutStream(FileOutStr);
        InStream.ResetPosition();
        CopyStream(FileOutStr, InStream);
        CompressedFile.Close();

        // Prepare bsc compression command
        ExeProcessStartInfo.Arguments := StrSubstNo('e "%1" "%2" %3 -b200', TempFileName, TempFileName + '.bsc', CompressionArguments);
        ExeProcess.StartInfo := ExeProcessStartInfo;

        // Start process and wait
        if not ExeProcess.Start() then begin
            if Erase(TempFileName) then;
            Error('Failed to start bsc.exe process.');
        end;
        ExeProcess.WaitForExit();

        // Remove input file
        if Erase(TempFileName) then;

        if ExeProcess.ExitCode() <> 0 then begin
            if Erase(TempFileName + '.bsc') then; // remove output if any
            Error('Compression process failed. Exit code: %1', ExeProcess.ExitCode());
        end;
        ExeProcess.Close();

        // Read the output file in blob
        CompressedFile.Open(TempFileName + '.bsc');
        CompressedFile.CreateInStream(InStream);
        CopyStream(OutStream, InStream);
        CompressedFile.Close();
        if Erase(TempFileName + '.bsc') then;
    end;

    procedure LibbscDecompressStream(InStream: InStream; OutStream: OutStream) DecompressedSize: Integer
    var
        DecompressedFile: File;
        FileOutStr: OutStream;
    begin
        InitBsc();

        // Save the stream to a temp file on the server
        if Erase(TempFileName) then;
        DecompressedFile.WriteMode(true);
        if not DecompressedFile.Create(TempFileName) then
            Error('Unable to create file %1', TempFileName);
        DecompressedFile.CreateOutStream(FileOutStr);
        InStream.ResetPosition();
        CopyStream(FileOutStr, InStream);
        DecompressedFile.Close();

        // Run bsc decompression command
        ExeProcessStartInfo.Arguments := StrSubstNo('d "%1" "%2"', TempFileName, TempFileName + '.dec');
        ExeProcess.StartInfo := ExeProcessStartInfo;

        // Start process and wait
        if not ExeProcess.Start() then begin
            if Erase(TempFileName) then;
            Error('Failed to start bsc.exe process.');
        end;

        ExeProcess.WaitForExit();

        if Erase(TempFileName) then;

        if ExeProcess.ExitCode() <> 0 then begin
            if Erase(TempFileName + '.dec') then;
            Error('Decompression process failed. Exit code: %1', ExeProcess.ExitCode());
        end;
        ExeProcess.Close();

        // Read decompressed file into OutStream
        DecompressedFile.Open(TempFileName + '.dec');
        DecompressedFile.CreateInStream(InStream);
        CopyStream(OutStream, InStream);
        DecompressedFile.Close();
        if Erase(TempFileName + '.dec') then;
    end;

    local procedure InitBsc()
    begin
        InitExe('bsc.exe');
    end;

    local procedure InitExe(ExeName: Text)
    var
        fileMgt: Codeunit "File Management";
    begin
        ExePath := System.ApplicationPath() + 'Add-ins\' + ExeName;
        if not Exists(ExePath) then begin
            ExePath := System.ApplicationPath() + ExeName;
            if not Exists(ExePath) then
                Error('Unable to locate the executable %1. The program should be placed in addin folder : %2', ExeName, System.ApplicationPath() + 'Add-ins\');
        end;

        // look for ram disk
        if Exists('R:\Temp') then
            TempFileName := 'R:\Temp\libbsc' + DelChr(Format(CreateGuid()), '=', '{} -') + '.tmp'
        else
            TempFileName := fileMgt.ServerTempFileName('');
        if Erase(TempFileName) then; // in case last batch bugged

        ExeProcess := ExeProcess.Process();
        ExeProcessStartInfo := ExeProcessStartInfo.ProcessStartInfo();
        ExeProcessStartInfo.FileName := ExePath;
        ExeProcessStartInfo.UseShellExecute := false;
        ExeProcessStartInfo.CreateNoWindow := true;
        ExeProcess.StartInfo := ExeProcessStartInfo;
        //end;
    end;
#endif
    #endregion

    #region Kanzi
#if ONPREM
    procedure KanziCompressStream(InStream: InStream; OutStream: OutStream)
    begin
        RunExeOnStream('kanzi.exe', '-c --input="%1" --output="%2" -f -t TEXT+UTF -e TPAQ -b 4m -j 8', '.knz', InStream, OutStream);
    end;

    procedure KanziDecompressStream(InStream: InStream; OutStream: OutStream)
    begin
        RunExeOnStream('kanzi.exe', '-d --input="%1" --output="%2"', '.dec', InStream, OutStream);
    end;

    /// <summary>
    /// Writes the input stream to a temp file, runs ExeName with ArgsPattern (%1 = input file, %2 = output file),
    /// then copies the produced file back into OutStream. Temp files are always erased.
    /// </summary>
    local procedure RunExeOnStream(ExeName: Text; ArgsPattern: Text; OutSuffix: Text; InStream: InStream; OutStream: OutStream)
    var
        WorkFile: File;
        FileOutStr: OutStream;
        OutFileName: Text;
    begin
        InitExe(ExeName);
        OutFileName := TempFileName + OutSuffix;

        // Save the stream to a temp file on the server
        if Erase(OutFileName) then;
        WorkFile.WriteMode(true);
        if not WorkFile.Create(TempFileName) then
            Error('Unable to create file %1', TempFileName);
        WorkFile.CreateOutStream(FileOutStr);
        InStream.ResetPosition();
        CopyStream(FileOutStr, InStream);
        WorkFile.Close();

        ExeProcessStartInfo.Arguments := StrSubstNo(ArgsPattern, TempFileName, OutFileName);
        ExeProcess.StartInfo := ExeProcessStartInfo;

        if not ExeProcess.Start() then begin
            if Erase(TempFileName) then;
            Error('Failed to start %1 process.', ExeName);
        end;
        ExeProcess.WaitForExit();

        if Erase(TempFileName) then;

        if ExeProcess.ExitCode() <> 0 then begin
            if Erase(OutFileName) then;
            Error('%1 process failed. Exit code: %2', ExeName, ExeProcess.ExitCode());
        end;
        ExeProcess.Close();

        // Read the output file back into the stream
        WorkFile.Open(OutFileName);
        WorkFile.CreateInStream(InStream);
        CopyStream(OutStream, InStream);
        WorkFile.Close();
        if Erase(OutFileName) then;
    end;
#endif
    #endregion

    #region ZStandard
#if ONPREM
    procedure ZstandardCompressStream(InStream: InStream; OutStream: OutStream; CompressionLevel: Integer)
    var
        Compressed: DotNet Array;
        DotNetArray: DotNet Array;
        DotNetByte: DotNet Byte;
        CompressedStream: DotNet MemoryStream;
        DotNetStream: DotNet Stream;
        CompressionOptions: DotNet TOOZstdCompressionOptions;
        Compressor: DotNet TOOZstdCompressor;
    begin
        DotNetStream := InStream;
        DotNetByte := 0;
        DotNetArray := DotNetArray.CreateInstance(DotNetByte.GetType(), InStream.Length());
        DotNetStream.Position := 0;
        DotNetStream.Read(DotNetArray, 0, InStream.Length());

        CompressionOptions := CompressionOptions.CompressionOptions(CompressionLevel);
        Compressor := Compressor.Compressor(CompressionOptions);
        Compressed := Compressor.Wrap(DotNetArray);
        Compressor.Dispose();
        Clear(DotNetArray);

        // Wrap compressed data into .NET MemoryStream
        CompressedStream := CompressedStream.MemoryStream(Compressed);

        // Reset position before copy
        CompressedStream.Position := 0;
        CompressedStream.CopyTo(OutStream);
    end;

    procedure ZstandardDecompressStream(InStream: InStream; OutStream: OutStream)
    var
        Decompressed: DotNet Array;
        DotNetArray: DotNet Array;
        DotNetByte: DotNet Byte;
        OutMemStream: DotNet MemoryStream;
        DotNetStream: DotNet Stream;
        Decompressor: DotNet TOOZstdDecompressor;
    begin
        DotNetByte := 0;
        DotNetStream := InStream;

        // Convert InStream to byte[]
        DotNetArray := DotNetArray.CreateInstance(DotNetByte.GetType(), InStream.Length);
        DotNetStream.Position := 0;
        DotNetStream.Read(DotNetArray, 0, InStream.Length);
        DotNetStream.Dispose();

        // Deocmpress
        Decompressor := Decompressor.Decompressor();
        Decompressed := Decompressor.Unwrap(DotNetArray);

        // Wrap decompressed array into a stream
        OutMemStream := OutMemStream.MemoryStream(Decompressed);
        Decompressor.Dispose(); // Dispose compressor
        OutMemStream.CopyTo(OutStream);
    end;
#endif
    #endregion

    var
#if ONPREM
        ExePath: Text;
        TempFileName: Text;
        ExeProcess: DotNet TOOProcess;
        ExeProcessStartInfo: DotNet TOOProcessStartInfo;
#endif
}