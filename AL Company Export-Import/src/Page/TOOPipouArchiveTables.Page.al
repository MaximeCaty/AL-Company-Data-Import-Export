page 51009 "TOO Pipou Archive Tables"
{
    ApplicationArea = All;
    Caption = 'Company Archive Tables';
    DeleteAllowed = false;
    InsertAllowed = false;
    PageType = List;
    SourceTable = "TOO Pipou Archive Tables";

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Table ID"; Rec."Table ID")
                {
                    Editable = false;
                }
                field("Table Name"; Rec."Table Name")
                {
                    Editable = false;
                }
                field("Table Caption"; Rec."Table Caption")
                {
                    Editable = false;
                }
                field(DataPerCOompany; Rec.DataPerCompany)
                {
                    Editable = false;
                }
                field("No. Records"; Rec."No. of Records")
                {
                    Editable = false;
                }
                field("No. Fields"; Rec."No. Fields")
                {
                    Editable = false;
                }
                field("Thread Weight"; Rec."Thread Weight")
                {
                    Visible = false;
                }
                field("Matched Table ID"; Rec."Matched Table ID") { }
                field("Matched Table Name"; Rec."Matched Table Name") { }
                field("Is Dictionary Source"; Rec."Is Dictionary Source") { }
                field("Dictionary Entry Count"; Rec."Dictionary Entry Count") { }

            }
        }
    }
}