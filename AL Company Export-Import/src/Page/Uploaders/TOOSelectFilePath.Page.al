#if ONPREM
page 51013 "TOO Select File Path"
{
    Caption = 'Choose a file path';
    PageType = Card;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            group("File")
            {
                ShowCaption = false;

                field(FilePath; FilePath)
                {
                    Caption = 'File Name';

                    trigger OnValidate()
                    var
                        Fl: File;
                    begin
                        if not Fl.Open(FilePath) then
                            Error('Unable to Open the provided file path. Please check availability form the server instance and read permission for the busienss central service account.')
                        else begin
                            FileSize := format(Fl.Len() div (1024 * 1024)) + ' MB';
                            Fl.Close();
                        end;
                    end;
                }

                field(FileSize; FileSize)
                {
                    Caption = 'File Size';
                    Editable = false;
                }
            }
        }
    }

    procedure GetFilePath(): Text
    begin
        exit(FilePath);
    end;

    var
        FilePath: Text;
        FileSize: Text;
}
#endif