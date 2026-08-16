page 51014 "TOO Upload File JS"
{
    ApplicationArea = All;
    Caption = 'Upload large file using JS addin';
    PageType = Card;

    layout
    {
        area(Content)
        {
            group("File")
            {
                ShowCaption = false;

                field(FileName; FileName)
                {
                    Caption = 'File Name';
                    Editable = false;
                    ApplicationArea = All;
                }

                field(FileSize; FileSize)
                {
                    Caption = 'File Size';
                    Editable = false;
                    ApplicationArea = All;
                }
                field(Progression; Progression)
                {
                    Caption = 'Upload Progression';
                    Editable = false;
                    Enabled = false;
                    ApplicationArea = All;
                }
                field(UploadSpeed; UploadSpeed)
                {
                    Caption = 'Upload Speed';
                    Editable = false;
                    Enabled = false;
                    ApplicationArea = All;
                }
                field(EstRemainingDur; EstRemainingDur)
                {
                    Caption = 'Est. Remaining time';
                    Editable = false;
                    Enabled = false;
                    ApplicationArea = All;
                }

                usercontrol(ChunkedUploader; "TOO ChunkedFileUploader")
                {
                    ApplicationArea = All;

                    trigger StartUpload(UploadedFileName: Text; TotalSize: Integer)
                    begin
                        Clear(TempBlob);
                        TempBlob.CreateOutStream(OutStr, TextEncoding::Windows); // single byte text encoding
                        FileName := UploadedFileName;
                        FileSize := Format(TotalSize div (1024 * 1024)) + ' MB';
                        TotalSizeGlobal := TotalSize;
                        ReceivedSizeGlobal := 0;
                        Progression := ProgressBar(0, 12);
                        StartDT := CurrentDateTime;
                        LastChunkDT := CurrentDateTime;
                    end;

                    trigger UploadChunk(BinaryTextChunk: BigText; ChunkNumber: Integer)
                    var
                        ChunkSize: Integer;
                    begin
                        BinaryTextChunk.Write(OutStr);
                        ChunkSize := BinaryTextChunk.Length;
                        ReceivedSizeGlobal += ChunkSize;

                        // speed / duration
                        EstRemainingDur := Round((TotalSizeGlobal / ReceivedSizeGlobal * (CurrentDateTime - StartDT)) - (CurrentDateTime - StartDT), 1000);
                        UploadSpeed := Format(Round(ChunkSize / (CurrentDateTime - LastChunkDT) * 1000 / (1024 * 1024), 0.01)) + ' MB/S';

                        // Update progression
                        Progression := ProgressBar(ReceivedSizeGlobal / TotalSizeGlobal, 12);
                        LastChunkDT := CurrentDateTime;
                    end;

                    trigger FinishUpload()
                    begin
                        UploadSpeed := '';
                        EstRemainingDur := 0;
                        UploadCompleted := true;
                    end;

                    trigger UploadError(ErrorMessage: Text)
                    begin
                        Error(ErrorMessage);
                    end;
                }
            }
        }
    }

    procedure IsUploadCompleted(): Boolean
    begin
        exit(UploadCompleted);
    end;

    procedure GetInStream(var UploadedFileName: Text; var InStr: InStream)
    begin
        if not UploadCompleted then
            Error('No file were uploaded or completed.');
        UploadedFileName := FileName;
        TempBlob.CreateInStream(InStr)
    end;

    local procedure ProgressBar(ProgressPercent: Decimal; NbChar: Integer) AsciiResult: Text
    var
        i: Integer;
        ProgressChar: Integer;
    begin
        ProgressChar := Round(ProgressPercent * NbChar, 1, '<') + 1;
        for i := 1 to NbChar do begin
            if i < ProgressChar then
                AsciiResult += '▰'
            else
                if i = ProgressChar then
                    AsciiResult += '▴'
                else
                    AsciiResult += '▱';
            if i = NbChar div 2 then
                AsciiResult += Format(Round(ProgressPercent * 100, 1)).PadLeft(2, '0') + '%';
        end;
    end;

    var
        TempBlob: Codeunit "Temp Blob";
        UploadCompleted: Boolean;
        LastChunkDT: DateTime;
        StartDT: DateTime;
        EstRemainingDur: Duration;
        ReceivedSizeGlobal: Integer;
        TotalSizeGlobal: Integer;
        OutStr: OutStream;
        FileName: Text;
        FileSize: Text;
        Progression: Text;
        UploadSpeed: Text;
}