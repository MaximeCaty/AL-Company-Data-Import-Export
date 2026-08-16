page 51010 "TOO Pipou Archive Fields"
{
    ApplicationArea = All;
    Caption = 'Pipou Archive Tables Fields';
    DeleteAllowed = false;
    InsertAllowed = false;
    PageType = List;
    SourceTable = "TOO Pipou Archive Fields";

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Field ID"; Rec."Field ID")
                {
                    Editable = false;
                }
                field("Field Name"; Rec."Field Name")
                {
                    Editable = false;
                }
                field("Field Caption"; Rec."Field Caption")
                {
                    Editable = false;
                }
                field("Field Type"; Rec."Field Type")
                {
                    Editable = false;
                }
                field("Max Length"; Rec."Max Length")
                {
                    Editable = false;
                }
                field("Empty In Chunks List"; Rec."Empty In Chunks List")
                {
                    Editable = false;
                }
                field("Use Dictionary"; Rec."Use Dictionary")
                {
                    Editable = false;
                }
                field("Dictionary File Name"; Rec."Dictionary File Name")
                {
                    Editable = false;
                }
                field(MissingMatch; MatchSymbol)
                {
                    Caption = 'Match';
                    Editable = false;
                    Width = 2;
                }
                field("Matched Table ID"; Rec."Matched Table ID")
                {
                    Editable = false;
                } // for calcfield
                field("Matched Field ID"; Rec."Matched Field ID")
                {
                    trigger OnValidate()
                    begin
                        if Rec."Matched Field ID" <> 0 then
                            MatchSymbol := '✅'
                        else
                            MatchSymbol := '⛔';
                    end;
                }
                field("Matched Field Name"; Rec."Matched Field Name") { }
            }
        }
    }
    trigger OnAfterGetRecord()
    begin
        if Rec."Matched Field ID" <> 0 then
            MatchSymbol := '✅'
        else
            MatchSymbol := '⛔';
    end;

    var
        MatchSymbol: Text[2];
}