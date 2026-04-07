codeunit 51002 "TOO Advanced Compression Mgt."
{
    procedure TextToEnum(CompressionModeText: Text) Compression: Enum "TOO Compression Algo."
    begin
        case CompressionModeText.ToLower().Trim() of
            '1', 'gzip', 'gz':
                Compression := Compression::Gzip;
            '3', 'zstandard', 'zst':
                Compression := Compression::zStandard;
            '4', 'libbsc', 'bsc':
                Compression := Compression::libbsc;
            '10', 'MCMX', 'mcmx':
                Compression := Compression::MCMX;
            '5', 'auto':
                Compression := Compression::"Auto (On-Premise)";
        end;
    end;
    #region Gen Comp/Dec
    procedure Compress(InputStream: Instream; OutputStream: OutStream; CompressMode: enum "TOO Compression Algo.")
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
                ZStandardCompressStream(InputStream, OutputStream, 12); // Default level is 3 (1 - 19) : 3 = "very fast", 9 = "optimal", 19-22 = ultra

            CompressMode::libbsc:
                LibbscCompressStream(InputStream, OutputStream, 2); // Default level is 1 (0, 1 or 2) 2 have the best ratio, 0 and 1 does not have significent speed difference

            CompressMode::MCMX:
                McmxCompressStream(InputStream, OutputStream, 'm', 2); // Level form lowest to highest : z, t, f, m, h, x - Note "h" and "x" require twice RAM, use with caution
#endif
            else
                error('Compression method "%1" is not supported', CompressMode);
        end
    end;

    procedure Decompress(InputStream: Instream; OutputStream: OutStream; CompressMode: enum "TOO Compression Algo.")
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

            CompressMode::MCMX:
                McmxDecompressStream(InputStream, OutputStream);
#endif
            else
                error('Compression method unsupported');
        end
    end;

    #endregion


    #region Libbsc
#if ONPREM
    procedure LibbscCompressStream(InStream: InStream; OutStream: OutStream; CompressionLevel: Integer) CompressedSize: Integer
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

        // Prepare bsc compression command (using 50MB max block size)
        ExeProcessStartInfo.Arguments := STRSUBSTNO('e "%1" "%2" -e%3 -p -b75', TempFileName, TempFileName + '.bsc', CompressionLevel);
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
        ExeProcessStartInfo.Arguments := STRSUBSTNO('d "%1" "%2"', TempFileName, TempFileName + '.dec');
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
    var
        fileMgt: Codeunit "File Management";
    begin
        //if BscPath = '' then begin
        ExePath := System.ApplicationPath();
        ExePath += 'Add-ins\bsc.exe';
        if not Exists(ExePath) then
            if not Exists(System.ApplicationPath() + 'bsc.exe') then
                Error('Unable to locate the libbsc executable (bsc.exe). The program should be placed in addin folder : %1', System.ApplicationPath());

        // look for ram disk
        if Exists('R:\Temp') then
            TempFileName := 'R:\Temp\libbsc' + DELCHR(Format(CreateGuid()), '=', '{} -') + '.tmp'
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

    #region MCMX
#if ONPREM
    procedure MCMXCompressStream(InStream: InStream; OutStream: OutStream; CompressionLevel: Text[1]; Threads: Integer) CompressedSize: Integer
    var
        CompressedFile: File;
        FileOutStr: OutStream;
    begin
        InitMcmx();

        // Save the stream to a temp file on the server
        if Erase(TempFileName) then;
        CompressedFile.WriteMode(true);
        if not CompressedFile.Create(TempFileName) then
            Error('Unable to create file %1', TempFileName);
        CompressedFile.CreateOutStream(FileOutStr);
        InStream.ResetPosition();
        CopyStream(FileOutStr, InStream);
        CompressedFile.Close();

        // Prepare compression command (using 50MB max block size)
        if Threads > 1 then
            ExeProcessStartInfo.Arguments := STRSUBSTNO('-%1 -threads %2 "%3" "%4"', CompressionLevel.ToLower(), Threads, TempFileName, TempFileName + '.mcmx', CompressionLevel)
        else
            ExeProcessStartInfo.Arguments := STRSUBSTNO('-%1 "%2" "%3"', CompressionLevel.ToLower(), TempFileName, TempFileName + '.mcmx', CompressionLevel);
        ExeProcess.StartInfo := ExeProcessStartInfo;

        // Start process and wait
        if not ExeProcess.Start() then begin
            if Erase(TempFileName) then;
            Error('Failed to start mcmx.exe process.');
        end;
        ExeProcess.WaitForExit();

        // Remove input file
        if Erase(TempFileName) then;

        if ExeProcess.ExitCode() <> 0 then begin
            if Erase(TempFileName + '.mcmx') then; // remove output if any
            Error('Compression process failed. Exit code: %1', ExeProcess.ExitCode());
        end;
        ExeProcess.Close();

        // Read the output file in blob
        CompressedFile.Open(TempFileName + '.mcmx');
        CompressedFile.CreateInStream(InStream);
        CopyStream(OutStream, InStream);
        CompressedFile.Close();
        if Erase(TempFileName + '.mcmx') then;
    end;

    procedure McmxDecompressStream(InStream: InStream; OutStream: OutStream) DecompressedSize: Integer
    var
        DecompressedFile: File;
        FileOutStr: OutStream;
    begin
        InitMcmx();

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
        ExeProcessStartInfo.Arguments := STRSUBSTNO('d "%1" "%2"', TempFileName, TempFileName + '.dec');
        ExeProcess.StartInfo := ExeProcessStartInfo;

        // Start process and wait
        if not ExeProcess.Start() then begin
            if Erase(TempFileName) then;
            Error('Failed to start mcmx.exe process.');
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

    local procedure InitMcmx()
    var
        fileMgt: Codeunit "File Management";
    begin
        //if BscPath = '' then begin
        ExePath := System.ApplicationPath();
        ExePath += 'Add-ins\mcmx.exe';
        if not Exists(ExePath) then
            if not Exists(System.ApplicationPath() + 'mcmx.exe') then
                Error('Unable to locate MCMX executable (mcmx.exe). The program should be placed in addin folder : %1', System.ApplicationPath());

        // look for ram disk
        if Exists('R:\Temp') then
            TempFileName := 'R:\Temp\mcmx' + DELCHR(Format(CreateGuid()), '=', '{} -') + '.tmp'
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

    #region ZStandard
#if ONPREM
    procedure ZstandardCompressStream(InStream: InStream; OutStream: OutStream; CompressionLevel: Integer)
    var
        DotNetByte: DotNet Byte;
        DotNetArray: DotNet Array;
        CompressedStream: Dotnet MemoryStream;
        Compressed: DotNet Array;
        DotNetStream: DotNet Stream;
        Compressor: DotNet TOOZstdCompressor;
        CompressionOptions: DotNet TOOZstdCompressionOptions;
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
        DotNetStream: Dotnet Stream;
        DotNetByte: DotNet Byte;
        DotNetArray: DotNet Array;
        Decompressed: DotNet Array;
        Decompressor: DotNet TOOZstdDecompressor;
        OutMemStream: Dotnet MemoryStream;
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
        ExeProcessStartInfo: Dotnet TOOProcessStartInfo;
#endif
}