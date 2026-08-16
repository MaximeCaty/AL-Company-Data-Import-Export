table 51007 "TOO Pipou Archive Tables"
{
    DataClassification = SystemMetadata;
    DataPerCompany = false;
    DrillDownPageId = "TOO Pipou Archive Tables";
    LookupPageId = "TOO Pipou Archive Tables";

    fields
    {
        field(1; "Archive ID"; Guid) { }
        field(10; "Table ID"; Integer) { }
        field(20; "Table Name"; Text[150]) { }
        field(25; "Table Caption"; Text[150]) { }
        field(30; DataPerCompany; Boolean)
        {
            Editable = false;
        }
        field(40; "No. of Records"; Integer) { }
        field(90; "Table DataClassification"; Integer) { }
        field(100; "No. Fields"; Integer)
        {
            CalcFormula = count("TOO Pipou Archive Fields" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID")));
            Editable = false;
            FieldClass = FlowField;
        }
        field(900; "Select For Import"; Boolean) { }
        field(910; "Import Completed"; Boolean)
        {
            CalcFormula = - exist("TOO Pipou Archive Files" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID"), Imported = const(false)));
            Editable = false;
            FieldClass = FlowField;
        }
        field(1000; "Matched Table ID"; Integer)
        {
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
            CalcFormula = lookup("Table Metadata".Name where(ID = field("Matched Table ID")));
            Editable = false;
            FieldClass = FlowField;
        }
        field(1020; "Match Status"; Enum "TOO Table Match Status")
        {
            Editable = false;
        }
        field(1030; "PreImport Truncated"; Boolean)
        {
            Editable = false;
        }
        field(1040; "Indexes Disabled"; Boolean)
        {
            Caption = 'Indexes Disabled', Comment = 'Index désactivés';
            Editable = false;
        }
        field(1050; "Disabled Indexes Count"; Integer)
        {
            Caption = 'Disabled Indexes', Comment = 'Index désactivés';
            Editable = false;
        }
        field(1100; "Is Dictionary Source"; Boolean)
        {
            Caption = 'Dictionary Source', Comment = 'Source de dictionnaire';
            Editable = false;
        }
        field(1110; "Dictionary Entry Count"; Integer)
        {
            Caption = 'Dictionary Entries', Comment = 'Entrées du dictionnaire';
            Editable = false;
        }
        field(1120; "Export Order"; Integer)
        {
            Caption = 'Export Order', Comment = 'Ordre d''export';
            Editable = false;
        }
        field(2000; "Affected Thread"; Integer) { }
        field(2010; "Thread Weight"; Integer)
        {
            Caption = 'Thread Weight', Comment = 'Poids pour les threads';
            Editable = false;
        }
        field(3000; "Rem. Rec. To Import"; Integer)
        {
            CalcFormula = sum("TOO Pipou Archive Files"."Number Of Recs" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID"), Imported = const(false)));
            Editable = false;
            FieldClass = FlowField;
        }
    }

    keys
    {
        key(Key1; "Archive ID", "Table ID")
        {
            Clustered = true;
        }
        key(WeightSort; "Archive ID", "Thread Weight") { }
        // Covers the table loop of an export thread : range on the thread, sorted by export order
        key(ExportOrder; "Archive ID", "Affected Thread", "Export Order", "Table ID") { }
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