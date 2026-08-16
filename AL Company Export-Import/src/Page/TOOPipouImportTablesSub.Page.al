page 51019 "TOO Pipou Import Tables Sub"
{
    ApplicationArea = All;
    Caption = 'Tables to Import';
    DeleteAllowed = false;
    InsertAllowed = false;
    PageType = ListPart;
    SourceTable = "TOO Pipou Archive Tables";

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Select For Import"; Rec."Select For Import") { }
                field("Table ID"; Rec."Table ID")
                {
                    Editable = false;
                }
                field("Table Name"; Rec."Table Name")
                {
                    Editable = false;
                }
                field(DataPerCompany; Rec.DataPerCompany) { }
                field("Table Caption"; Rec."Table Caption")
                {
                    Editable = false;
                }
                field("No. Records"; Rec."No. of Records")
                {
                    Editable = false;
                }
                field("Match Status"; Rec."Match Status") { }
                field("Matched Table ID"; Rec."Matched Table ID") { }
                field("Matched Table Name"; Rec."Matched Table Name") { }
                field("No. Fields"; Rec."No. Fields")
                {
                    Editable = false;
                }

            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(ClearSelect)
            {
                Caption = 'Clear Selection';
                Image = ClearFilter;

                trigger OnAction()
                begin
                    Rec.SetRange("Archive ID", Rec."Archive ID");
                    Rec.ModifyAll("Select For Import", false);
                end;
            }
            action(SelectAll)
            {
                Caption = 'Select All';
                Image = AllLines;

                trigger OnAction()
                begin
                    Rec.SetRange("Archive ID", Rec."Archive ID");
                    Rec.ModifyAll("Select For Import", true);
                end;
            }
            action(ExclArch)
            {
                Caption = 'Exclude Archives';
                Image = Archive;

                trigger OnAction()
                begin
                    Rec.SetFilter("Table Name", '* Archive*|* Archives*');
                    Rec.ModifyAll("Select For Import", false);
                    Rec.SetRange("Table Name");
                end;
            }
            action(ExclLogs)
            {
                Caption = 'Exclude Log';
                Image = Log;

                trigger OnAction()
                begin
                    Rec.SetFilter("Table Name", '* Log|* Logs|*Log Entry*');
                    Rec.ModifyAll("Select For Import", false);
                    Rec.SetRange("Table Name");
                end;
            }
        }
    }
}