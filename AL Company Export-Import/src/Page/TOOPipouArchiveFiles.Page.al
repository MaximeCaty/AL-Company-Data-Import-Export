page 51005 "TOO Pipou Archive Files"
{
    ApplicationArea = All;
    Caption = 'Company Archive Files';
    Editable = false;
    PageType = List;
    SourceTable = "TOO Pipou Archive Files";

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("File Name"; Rec."File Name") { }
                field("Table ID"; Rec."Table ID") { }
                field("Original Table Name"; Rec."Original Table Name") { }
                field("Original Table Caption"; Rec."Original Table Caption") { }
                field("No. of Fields"; Rec."No. of Fields") { }
                field("Number Of Recs"; Rec."Number Of Recs") { }
                field("Chunk No."; Rec."Chunk No.") { }
                field(Imported; Rec.Imported) { }
                field("Column Storage"; Rec."Column Storage") { }
                field("Compression Mode"; Rec."Compression Mode") { }
                field("Comp. Ratio"; Rec."Comp. Ratio") { }
                field("Compressed Length"; Rec."Compressed Length") { }
                field("Uncompressed Length"; Rec."Uncompressed Length") { }
                field("Start Index"; Rec."Start Index") { }
                field("End Index"; Rec."End Index") { }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(Download)
            {
                Caption = 'Decompress & download file';
                Image = Download;
                Promoted = true;
                PromotedCategory = Process;
                PromotedIsBig = true;
                PromotedOnly = true;

                trigger OnAction()
                var
                    Arch: Record "TOO Pipou Archive";
                    TempBlob: Codeunit "Temp Blob";
                    AdvCompMgt: Codeunit "TOO Advanced Compression Mgt.";
                    Win: Dialog;
                    InStr: InStream;
                    OutStr: OutStream;
                    Tofile: Text;
                begin
                    Rec.CalcFields(Data);
                    if not Rec.Data.HasValue then
                        Error('No data stored on this record.');

                    if Rec."Compression Mode" in [Rec."Compression Mode"::None] then
                        Rec.Data.CreateInStream(InStr)
                    else begin
                        // Decompress
                        Win.Open('Decompressing using ' + Format(Rec."Compression Mode"));
                        Rec.Data.CreateInStream(InStr);
                        TempBlob.CreateOutStream(OutStr);
                        AdvCompMgt.Decompress(InStr, OutStr, Rec."Compression Mode");
                        TempBlob.CreateInStream(InStr);
                        Win.Close();
                    end;

                    // Create file name
                    if Rec."File Name".LastIndexOf('.') > 0 then
                        Tofile := CopyStr(Rec."File Name", 1, Rec."File Name".LastIndexOf('.') - 1)
                    else
                        Tofile := Rec."File Name";
                    Arch.Get(Rec."Archive Name", Rec."Archive ID");
                    if Rec."Column Storage" then
                        Tofile += '.colstore'
                    else
                        Tofile += '.bin';

                    // Download
                    DownloadFromStream(InStr, '', '', '', Tofile);
                end;
            }
        }
    }
}