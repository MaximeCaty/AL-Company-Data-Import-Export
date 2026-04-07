page 51020 "TOO Pipou Threads"
{
    Caption = 'Import/Export Active Threads';
    PageType = ListPart;
    SourceTable = "TOO Pipou Thread";
    Editable = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field("Thread No."; Rec."Thread No.")
                {
                    ApplicationArea = All;
                }
                field(SystemCreatedAt; Rec.SystemCreatedAt)
                {
                    ApplicationArea = All;
                }
                field(Status; Rec.Status)
                {
                    ApplicationArea = All;
                }
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
                field("Current Table"; Rec."Current Table")
                {
                    ApplicationArea = All;
                }
                field("Current File"; Rec."Current File")
                {
                    ApplicationArea = All;
                }
                field("Current File Progress %"; Rec."Current File Progress %")
                {
                    ApplicationArea = All;
                }
                field("Total Rec. Proceed"; Rec."Total Rec. Proceed")
                {
                    ApplicationArea = All;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        if Rec."Total Rec. To Process" = 0 then begin
            ThreadProgressBar := ProgressBar(0);
            ThreadProgress := 0;
        end else begin
            ThreadProgressBar := ProgressBar(Rec."Total Rec. Proceed" / Rec."Total Rec. To Process");
            ThreadProgress := Round(Rec."Total Rec. Proceed" / Rec."Total Rec. To Process" * 100, 1);
        end;
    end;

    procedure ProgressBar(ProgressPercent: Decimal) AsciiResult: Text
    var
        i: Integer;
        ProgressChar: Integer;
    begin
        ProgressChar := Round(ProgressPercent * 24, 1, '<') + 1;
        for i := 1 to 12 do begin
            if i < ProgressChar then
                AsciiResult += '▰'
            else
                if i = ProgressChar then
                    AsciiResult += '▴'
                else
                    AsciiResult += '▱';
        end;
    end;


    var
        ThreadProgressBar: Text[20];
        ThreadProgress: Integer;
}