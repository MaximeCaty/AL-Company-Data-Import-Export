page 51020 "TOO Pipou Threads"
{
    ApplicationArea = All;
    Caption = 'Import/Export Active Threads';
    Editable = false;
    PageType = ListPart;
    SourceTable = "TOO Pipou Thread";

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("Thread No."; Rec."Thread No.") { }
                field(SystemCreatedAt; Rec.SystemCreatedAt) { }
                field(Status; Rec.Status) { }
                field(ThreadProgress; ThreadProgress)
                {
                    Caption = 'Progression %';
                }
                field(ThreadProgressBar; ThreadProgressBar)
                {
                    Caption = 'Progress Bar';
                    Editable = false;
                    Width = 15;
                }
                field("Current Table"; Rec."Current Table") { }
                field("Current File"; Rec."Current File") { }
                field("Current File Progress %"; Rec."Current File Progress %") { }
                field("Total Rec. Proceed"; Rec."Total Rec. Proceed") { }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        if Rec."Total Rec. To Process" = 0 then begin
            ThreadProgressBar := ProgressBar(0, 15);
            ThreadProgress := 0;
        end else begin
            ThreadProgressBar := ProgressBar(Rec."Total Rec. Proceed" / Rec."Total Rec. To Process", 15);
            ThreadProgress := Round(Rec."Total Rec. Proceed" / Rec."Total Rec. To Process" * 100, 1);
        end;
    end;

    procedure ProgressBar(ProgressPercent: Decimal; Length: Integer) AsciiResult: Text
    var
        i: Integer;
        ProgressChar: Integer;
    begin
        ProgressChar := Round(ProgressPercent * Length, 1, '<') + 1;
        for i := 1 to Length do
            if i < ProgressChar then
                AsciiResult += '▰'
            else
                if i = ProgressChar then
                    AsciiResult += '▴'
                else
                    AsciiResult += '▱';
    end;


    var
        ThreadProgress: Integer;
        ThreadProgressBar: Text[20];
}