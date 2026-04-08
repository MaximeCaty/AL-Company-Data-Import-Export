page 51019 "TOO Pipou Import Tables Sub"
{
    PageType = ListPart;
    SourceTable = "TOO Pipou Archive Tables";
    InsertAllowed = false;
    DeleteAllowed = false;
    Caption = 'Tables to Import';
    ApplicationArea = All;

    layout
    {
        area(Content)
        {
            repeater(Lst)
            {
                field("Select For Import"; Rec."Select For Import") { }
                field("Table ID"; Rec."Table ID") { Editable = false; }
                field("Table Name"; Rec."Table Name") { Editable = false; }
                field("Table Caption"; Rec."Table Caption") { Editable = false; }
                field("No. Records"; Rec."No. of Records") { Editable = false; }
                field("Match Status"; Rec."Match Status") { }
                field("Matched Table ID"; Rec."Matched Table ID") { }
                field("Matched Table Name"; Rec."Matched Table Name") { }
                field("No. Fields"; Rec."No. Fields") { Editable = false; }

            }
        }
    }
    actions
    {
        area(Processing)
        {
            action(ClearSelect)
            {
                ApplicationArea = all;
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
                ApplicationArea = all;
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
                ApplicationArea = all;
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
                ApplicationArea = all;
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