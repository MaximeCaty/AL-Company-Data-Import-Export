table 51007 "TOO Pipou Archive Tables"
{
    DataClassification = SystemMetadata;
    DrillDownPageId = "TOO Pipou Archive Tables";
    LookupPageId = "TOO Pipou Archive Tables";

    fields
    {
        field(1; "Archive ID"; Guid)
        {
            DataClassification = SystemMetadata;
        }
        field(10; "Table ID"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(20; "Table Name"; Text[150])
        {
            DataClassification = SystemMetadata;
        }
        field(25; "Table Caption"; Text[150])
        {
            DataClassification = SystemMetadata;
        }
        field(30; DataPerCompany; Boolean)
        {
            DataClassification = SystemMetadata;
        }
        field(40; "No. of Records"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(50; "Record Size"; Decimal)
        {
            DataClassification = SystemMetadata;
        }
        field(60; "Original SQL Data+Index (KB)"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(70; "Original Data Size (KB)"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(80; "Original Index Size (KB)"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(90; "Table DataClassification"; Integer)
        {

        }
        field(100; "No. Fields"; Integer)
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = count("TOO Pipou Archive Fields" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID")));
        }
        field(900; "Select For Import"; Boolean)
        {
            ToolTip = 'Indicate if the table has been selected for next import oepration.';
        }
        field(910; "Import Completed"; Boolean)
        {
            ToolTip = 'Indicate if the table has been completly imported.';
            FieldClass = FlowField;
            CalcFormula = - exist("TOO Pipou Archive Files" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID"), Imported = const(false)));
        }
        field(1000; "Matched Table ID"; Integer)
        {
            DataClassification = SystemMetadata;
            TableRelation = "Table Metadata";

            trigger OnValidate()
            var
                ArchFields: Record "TOO Pipou Archive Fields";
            begin
                // Match field
                if xRec."Matched Table ID" <> Rec."Matched Table ID" then begin
                    ArchFields.SetRange("Archive ID", Rec."Archive ID");
                    ArchFields.SetRange("Table ID", Rec."Table ID");
                    ArchFields.FindSet();
                    repeat
                        ArchFields.SearchMatchingField(Rec."Matched Table ID");
                        ArchFields.Modify();
                    until ArchFields.Next() = 0;
                end;
                UpdateMatchStatus();
            end;
        }
        field(1010; "Matched Table Name"; Text[150])
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup("Table Metadata".Name where(ID = field("Matched Table ID")));
        }
        field(1020; "Match Status"; Enum "TOO Table Match Status")
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(1030; "PreImport Truncated"; Boolean)
        {
            Editable = false;
        }
        field(2000; "Affected Thread"; Integer)
        {
            DataClassification = SystemMetadata;
        }
    }

    keys
    {
        key(Key1; "Archive ID", "Table ID")
        {
            Clustered = true;
        }
        key(SortSize; "Archive ID", "Original SQL Data+Index (KB)")
        {

        }
    }

    procedure UpdateMatchStatus()
    var
        ArchFields: Record "TOO Pipou Archive Fields";
    begin
        if Rec."Matched Table ID" = 0 then
            Rec."Match Status" := Rec."Match Status"::Missing
        else begin
            ArchFields.SetRange("Archive ID", Rec."Archive ID");
            ArchFields.SetRange("Table ID", Rec."Table ID");
            ArchFields.SetRange("Matched Field ID", 0);
            if ArchFields.IsEmpty then
                Rec."Match Status" := Rec."Match Status"::Full
            else begin
                ArchFields.SetFilter("Matched Field ID", '<>0');
                if not ArchFields.IsEmpty then
                    Rec."Match Status" := Rec."Match Status"::Partial
                else
                    Rec."Match Status" := Rec."Match Status"::Missing;
            end;
        end;
        if Rec."Match Status" <> Rec."Match Status"::Full then
            Rec."Select For Import" := false;
    end;
}