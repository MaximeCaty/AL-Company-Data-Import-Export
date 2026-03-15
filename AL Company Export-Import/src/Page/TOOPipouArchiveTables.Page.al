page 51009 "TOO Pipou Archive Tables"
{
    PageType = List;
    ApplicationArea = All;
    SourceTable = "TOO Pipou Archive Tables";
    InsertAllowed = false;
    DeleteAllowed = false;
    Caption = 'Pipou Archive Tables';

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Table ID"; Rec."Table ID") { Editable = false; }
                field("Table Name"; Rec."Table Name") { Editable = false; }
                field("Table Caption"; Rec."Table Caption") { Editable = false; }
                field(DataPerCOompany; Rec.DataPerCompany) { Editable = false; }
                field("No. Records"; Rec."No. of Records") { Editable = false; }
                field("No. Fields"; Rec."No. Fields") { Editable = false; }
                field("Record Size"; Rec."Record Size") { Editable = false; }
                field("Total Size (KB)"; Rec."Original SQL Data+Index (KB)") { Editable = false; }
                field("Total Data Size (KB)"; Rec."Original Data Size (KB)") { Editable = false; }
                field("Total Index Size (KB)"; Rec."Original Index Size (KB)") { Editable = false; }
                field("Matched Table ID"; Rec."Matched Table ID") { }
                field("Matched Table Name"; Rec."Matched Table Name") { }

            }
        }
    }
}