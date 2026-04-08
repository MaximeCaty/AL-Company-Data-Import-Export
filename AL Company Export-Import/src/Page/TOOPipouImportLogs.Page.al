page 51006 "TOO Pipou Import Logs"
{
    PageType = List;
    SourceTable = "TOO Pipou Import Log";
    ModifyAllowed = False;
    InsertAllowed = false;
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(lst)
            {
                field("Thread No."; Rec."Thread No.")
                {
                    ApplicationArea = All;
                }
                field("Entry No."; Rec."Entry No.")
                {
                    ApplicationArea = All;
                }
                field("Table ID"; Rec."Table ID")
                {
                    ApplicationArea = All;
                }
                field("Table Name"; Rec."Table Name")
                {
                    ApplicationArea = All;
                }
                field("Chunk Entry No."; Rec."Chunk Entry No.")
                {
                    ApplicationArea = All;
                }
                field(Status; Rec.Status)
                {
                    ApplicationArea = All;
                }
                field("Action"; Rec.Action)
                {
                    ApplicationArea = All;
                }
                field("Message"; Rec.Message)
                {
                    ApplicationArea = All;
                }
                field(CallStack; Rec.CallStack)
                {
                    ApplicationArea = all;
                }
            }
        }
    }
}