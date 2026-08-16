page 51006 "TOO Pipou Import Logs"
{
    ApplicationArea = All;
    InsertAllowed = false;
    ModifyAllowed = false;
    PageType = List;
    SourceTable = "TOO Pipou Import Log";

    layout
    {
        area(Content)
        {
            repeater(lst)
            {
                field("Thread No."; Rec."Thread No.") { }
                field("Entry No."; Rec."Entry No.") { }
                field("Table ID"; Rec."Table ID") { }
                field("Table Name"; Rec."Table Name") { }
                field("Chunk Entry No."; Rec."Chunk Entry No.") { }
                field(Status; Rec.Status) { }
                field("Action"; Rec.Action) { }
                field(Message; Rec.Message) { }
                field(CallStack; Rec.CallStack) { }
            }
        }
    }
}