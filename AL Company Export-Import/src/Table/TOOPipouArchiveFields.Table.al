table 51008 "TOO Pipou Archive Fields"
{
    DataClassification = SystemMetadata;
    DataPerCompany = false;
    DrillDownPageId = "TOO Pipou Archive Fields";
    LookupPageId = "TOO Pipou Archive Fields";

    fields
    {
        field(1; "Archive ID"; Guid) { }
        field(10; "Table ID"; Integer) { }
        field(30; "Field ID"; Integer) { }
        field(40; "Field Name"; Text[150]) { }
        field(45; "Field Caption"; Text[150]) { }
        field(50; "Field Type"; Enum "TOO Fields Types") { }
        field(55; "Field Type Name"; Text[30]) { }
        field(60; "Max Length"; Integer) { }
        field(70; "Part of Primary Key"; Boolean) { }
        field(80; "Empty In Chunks List"; Text[150]) { }
        field(100; "Field DataClassification"; Integer) { }
        field(990; "Matched Table ID"; Integer)
        {
            CalcFormula = lookup("TOO Pipou Archive Tables"."Matched Table ID" where("Archive ID" = field("Archive ID"), "Table ID" = field("Table ID")));
            Editable = false;
            FieldClass = FlowField;
        }
        field(1000; "Matched Field ID"; Integer)
        {
            TableRelation = Field where(TableNo = field("Matched Table ID"));

            trigger OnValidate()
            var
                ArchTable: Record "TOO Pipou Archive Tables";
            begin
                ArchTable.Get(Rec."Archive ID", Rec."Table ID");
                ArchTable.UpdateMatchStatus();
            end;
        }
        field(1010; "Matched Field Name"; Text[150])
        {
            CalcFormula = lookup(Field.FieldName where("No." = field("Matched Field ID"), TableNo = field("Table ID")));
            Editable = false;
            FieldClass = FlowField;
        }
        field(1100; "Use Dictionary"; Boolean)
        {
            Caption = 'Use Dictionary', Comment = 'Utilise un dictionnaire';
            Editable = false;
        }
        field(1110; "Dictionary File Name"; Text[70])
        {
            Caption = 'Dictionary', Comment = 'Dictionnaire';
            Editable = false;
        }
    }

    keys
    {
        key(Key1; "Archive ID", "Table ID", "Field ID")
        {
            Clustered = true;
        }
    }

    procedure SearchMatchingField(MatchedTableID: Integer)
    var
        Fields: Record Field;
    begin
        if Rec."Matched Table ID" = 0 then
            Rec.CalcFields("Matched Table ID");

        // Base Filter on Table No + Type
        Fields.SetRange(TableNo, MatchedTableID);
        Fields.SetRange("Type", Rec."Field Type");

        // 1. Same Name + Same ID
        Fields.SetRange("No.", Rec."Field ID");
        Fields.SetRange(FieldName, Rec."Field Name");
        if not Fields.IsEmpty then
            Rec."Matched Field ID" := Rec."Field ID"
        else begin
            // 2. Same ID only
            Fields.SetRange(FieldName);
            if Fields.FindFirst() then
                Rec."Matched Field ID" := Fields."No."
            else begin
                // 3. Same Name only
                Fields.SetRange("No.");
                Fields.SetRange(FieldName, Rec."Field Name");
                if Fields.FindFirst() then
                    Rec."Matched Field ID" := Fields."No."
                else begin
                    // 4. Same Caption + Only 1 match
                    Fields.SetRange(FieldName);
                    Fields.SetRange("Field Caption", Rec."Field Caption");
                    if Fields.FindFirst() then
                        if Fields.Count() = 1 then
                            Rec."Matched Field ID" := Fields."No."
                        else
                            Rec."Matched Field ID" := 0
                    else
                        Rec."Matched Field ID" := 0;
                end;
            end;
        end;
    end;
}