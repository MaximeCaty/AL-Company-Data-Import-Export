page 51014 "TOO Upload File JS"
{
    Caption = 'Upload large file using JS addin';
    PageType = Card;
    ApplicationArea = All;

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
                }

                field(FileSize; FileSize)
                {
                    Caption = 'File Size';
                    Editable = false;
                }
                field(Progression; Progression)
                {
                    Caption = 'Upload Progression';
                    Editable = false;
                    Enabled = false;
                }
                field(UploadSpeed; UploadSpeed)
                {
                    Caption = 'Upload Speed';
                    Editable = false;
                    Enabled = false;
                }
                field(EstRemainingDur; EstRemainingDur)
                {
                    Caption = 'Est. Remaining time';
                    Editable = false;
                    Enabled = false;
                }

                usercontrol(ChunkedUploader; "TOO ChunkedFileUploader")
                {
                    ApplicationArea = All;

                    trigger StartUpload(FileName: Text; TotalSize: Integer)
                    begin
                        clear(TempBlob);
                        TempBlob.CreateOutStream(OutStr, TextEncoding::Windows); // single byte text encoding
                        this.FileName := FileName;
                        FileSize := Format(TotalSize div (1024 * 1024)) + ' MB';
                        TotalSizeGlobal := TotalSize;
                        ReceivedSizeGlobal := 0;
                        Progression := ProgressBar(0, 12);
                        //Clear(TempFile);
                        StartDT := CurrentDateTime;
                        LastChunkDT := CurrentDateTime;
                    end;

                    trigger UploadChunk(BinaryTextChunk: Text; ChunkNumber: Integer)
                    var
                        ChunkSize: Integer;
                    begin
                        ChunkSize := StrLen(BinaryTextChunk);
                        OutStr.WriteText(BinaryTextChunk);
                        //TempFile.AddText(BinaryTextChunk);
                        ReceivedSizeGlobal += ChunkSize;

                        // speed / duration
                        EstRemainingDur := round((TotalSizeGlobal / ReceivedSizeGlobal * (CurrentDateTime - StartDT)) - (CurrentDateTime - StartDT), 1000);
                        UploadSpeed := Format(round(ChunkSize / (CurrentDateTime - LastChunkDT) * 1000 / (1024 * 1024), 0.01)) + ' MB/S';

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

    procedure GetInStream(var FileName: Text; var InStr: InStream)
    begin
        if not UploadCompleted then
            Error('No file were uploaded or completed.');
        FileName := this.FileName;
        //TempFile.Read(InStr);
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
        FileName: Text;
        FileSize: Text;
        ReceivedSizeGlobal: Integer;
        TotalSizeGlobal: Integer;
        TempBlob: Codeunit "Temp Blob";
        OutStr: OutStream;
        //TempFile: BigText;
        UploadCompleted: Boolean;
        Progression: Text;
        StartDT: DateTime;
        LastChunkDT: DateTime;
        EstRemainingDur: Duration;
        UploadSpeed: Text;
}