table 51008 "TOO Pipou Archive Fields"
{
    DataClassification = SystemMetadata;
    DrillDownPageId = "TOO Pipou Archive Fields";
    LookupPageId = "TOO Pipou Archive Fields";

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
        field(30; "Field ID"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(40; "Field Name"; Text[150])
        {
            DataClassification = SystemMetadata;
        }
        field(45; "Field Caption"; Text[150])
        {
            DataClassification = SystemMetadata;
        }
        field(50; "Field Type"; enum "TOO Fields Types")
        {
            DataClassification = SystemMetadata;
        }
        field(55; "Field Type Name"; Text[30])
        {
            DataClassification = SystemMetadata;
        }
        field(60; "Max Length"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(70; "Part of Primary Key"; Boolean)
        {
            DataClassification = SystemMetadata;
        }
        field(80; "Empty In Chunks List"; Text[150])
        {
            DataClassification = SystemMetadata;
        }
        field(100; "Field DataClassification"; Integer)
        {
            DataClassification = SystemMetadata;
        }
        field(990; "Matched Table ID"; Integer)
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup("TOO Pipou Archive Tables"."Matched Table ID" Where("Archive ID" = field("Archive ID"), "Table ID" = Field("Table ID")));
        }
        field(1000; "Matched Field ID"; Integer)
        {
            DataClassification = SystemMetadata;
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
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = lookup(Field.FieldName where("No." = field("Matched Field ID"), TableNo = field("Table ID")));
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